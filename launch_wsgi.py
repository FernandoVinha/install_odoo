import odoo
 
#----------------------------------------------------------
# Common
#----------------------------------------------------------
odoo.multi_process = True
 
# Equivalent of --load command-line option
odoo.conf.server_wide_modules = ['web']
conf = odoo.tools.config
 
# Path to the OpenERP Addons repository (comma-separated for
# multiple locations)
 
conf['addons_path'] = '/home/admin/odoo/addons'
 
# Optional database config if not using local socket
#conf['db_name'] = 'OdooSite'
conf['db_host'] = 'localhost'
conf['db_user'] = 'admin_pg_odoo'   # Same name as was declared in the start
conf['db_port'] = 5432
conf['db_password'] = 'admin'     # Same password as was declared in the start
 
#----------------------------------------------------------
# Generic WSGI handlers application
#----------------------------------------------------------
application = odoo.service.wsgi_server.application
 
odoo.service.server.load_server_wide_modules()
 
#----------------------------------------------------------
# Gunicorn
#----------------------------------------------------------
# Standard OpenERP XML-RPC port is 8069
bind = '127.0.0.1:8069'
pidfile = '.gunicorn.pid'
workers = 4
timeout = 240
max_requests = 2000