#!/bin/bash

# Variáveis de configuração
OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="12.0"
IS_ENTERPRISE="False"
OE_SUPERADMIN="admin"
OE_CONFIG="${OE_USER}-server"
PYTHON_VERSION="3.8"
VENV_PATH="/opt/odoo-venv"

# URL funcional de wkhtmltopdf
WKHTMLTOX_X64=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
WKHTMLTOX_X32=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_i386.deb

echo -e "\n---- Update Server ----"
sudo apt update && sudo apt upgrade -y

echo -e "\n---- Install Python 3.8 and Dependencies ----"
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.8 python3.8-venv python3.8-dev gcc libffi-dev libssl-dev libpq-dev \
  libxml2-dev libxslt1-dev zlib1g-dev libjpeg-dev libldap2-dev libsasl2-dev libtiff-dev libopenjp2-7-dev

echo -e "\n---- Create Python Virtual Environment ----"
python3.8 -m venv $VENV_PATH
source $VENV_PATH/bin/activate
pip install --upgrade pip wheel setuptools
pip install -r https://raw.githubusercontent.com/odoo/odoo/${OE_VERSION}/requirements.txt
pip install gevent==1.5.0
deactivate

echo -e "\n---- Install PostgreSQL Server ----"
sudo apt install postgresql -y
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

echo -e "\n---- Install Other Required Packages ----"
sudo apt install wget git gdebi-core -y

if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Install wkhtmltopdf ----"
  if [ "`getconf LONG_BIT`" == "64" ]; then
    _url=$WKHTMLTOX_X64
  else
    _url=$WKHTMLTOX_X32
  fi
  wget $_url
  sudo gdebi --n $(basename $_url)
  sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
  sudo ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
fi

echo -e "\n---- Create Odoo User and Directories ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
sudo adduser $OE_USER sudo
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER
sudo mkdir -p $OE_HOME/custom/addons
sudo chown -R $OE_USER:$OE_USER $OE_HOME/custom

echo -e "\n==== Installing ODOO Server ===="
if [ ! -d "$OE_HOME_EXT/.git" ]; then
  sudo rm -rf $OE_HOME_EXT
  sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/
fi

if [ $IS_ENTERPRISE = "True" ]; then
    sudo ln -sf /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"
    sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons"
    sudo pip install num2words ofxparse
    sudo apt install nodejs npm -y
    sudo npm install -g less less-plugin-clean-css
fi

echo -e "\n---- Creating Configuration File ----"
sudo tee /etc/${OE_CONFIG}.conf > /dev/null <<EOF
[options]
admin_passwd = ${OE_SUPERADMIN}
xmlrpc_port = ${OE_PORT}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons
EOF

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "\n---- Creating Startup Script ----"
sudo tee $OE_HOME_EXT/start.sh > /dev/null <<EOF
#!/bin/bash
source $VENV_PATH/bin/activate
exec python $OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
EOF

sudo chmod +x $OE_HOME_EXT/start.sh

echo -e "\n---- Creating Daemon Script ----"
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Odoo Server
# Description: Odoo init script with virtualenv
### END INIT INFO
PATH=/bin:/sbin:/usr/bin
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
USER=$OE_USER
CONFIGFILE="/etc/${OE_CONFIG}.conf"
PIDFILE=/var/run/\${NAME}.pid
DAEMON_OPTS="-c \$CONFIGFILE"
VENV_ACTIVATE="$VENV_PATH/bin/activate"
[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
  [ -f \$PIDFILE ] || return 1
  pid=\`cat \$PIDFILE\`
  [ -d /proc/\$pid ] && return 0
  return 1
}
case "\$1" in
  start)
    echo -n "Starting \$DESC: "
    start-stop-daemon --start --quiet --pidfile \$PIDFILE \\
      --chuid \$USER --background --make-pidfile \\
      --exec /bin/bash -- -c ". \$VENV_ACTIVATE && exec python \$DAEMON \$DAEMON_OPTS"
    echo "\$NAME."
    ;;
  stop)
    echo -n "Stopping \$DESC: "
    start-stop-daemon --stop --quiet --pidfile \$PIDFILE --oknodo
    echo "\$NAME."
    ;;
  restart|force-reload)
    \$0 stop
    sleep 1
    \$0 start
    ;;
  *)
    echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac
exit 0
EOF

sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
sudo chmod 755 /etc/init.d/$OE_CONFIG
sudo chown root: /etc/init.d/$OE_CONFIG
sudo update-rc.d $OE_CONFIG defaults

echo -e "\n---- Starting Odoo Service ----"
sudo /etc/init.d/$OE_CONFIG start

echo -e "\n-----------------------------------------------------------"
echo "✅ Odoo $OE_VERSION instalado com sucesso em Python $PYTHON_VERSION (venv)"
echo "Acesse: http://localhost:$OE_PORT"
echo "Start:   sudo service $OE_CONFIG start"
echo "Stop:    sudo service $OE_CONFIG stop"
echo "Restart: sudo service $OE_CONFIG restart"
echo "Log:     tail -f /var/log/$OE_USER/$OE_CONFIG.log"
echo "-----------------------------------------------------------"
