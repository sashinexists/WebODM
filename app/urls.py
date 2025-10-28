from django.urls import include, path, re_path
from django.views.i18n import JavaScriptCatalog

from .views import app as app_views, public as public_views, dev as dev_views
from .plugins.views import app_view_handler, root_url_patterns

from app.boot import boot
from webodm import settings
from app.plugins import sync_plugin_db

# Test cases call boot() independently
# Also don't execute boot with celery workers
if not settings.WORKER_RUNNING and not settings.TESTING:
    boot()

# During testing, boot() is not called (see above)
# but we need to know which plugins are available to mount the proper
# routes via urlpatterns.
if settings.TESTING:
    sync_plugin_db()

urlpatterns = [
    re_path(r'^$', app_views.index, name='index'),
    path('welcome/', app_views.welcome, name='welcome'),
    path('dashboard/', app_views.dashboard, name='dashboard'),
    re_path(r'^map/project/(?P<project_pk>[^/.]+)/task/(?P<task_pk>[^/.]+)/$', app_views.map, name='map'),
    re_path(r'^map/project/(?P<project_pk>[^/.]+)/$', app_views.map, name='map'),
    re_path(r'^3d/project/(?P<project_pk>[^/.]+)/task/(?P<task_pk>[^/.]+)/$', app_views.model_display, name='model_display'),

    re_path(r'^public/(?P<uuid_type>project|task)/(?P<uuid>[^/.]+)/map/$', public_views.map, name='public_map'),
    re_path(r'^public/(?P<uuid_type>project|task)/(?P<uuid>[^/.]+)/iframe/map/$', public_views.map_iframe, name='public_iframe_map'),
    re_path(r'^public/task/(?P<task_pk>[^/.]+)/3d/$', public_views.model_display, name='public_3d'),
    re_path(r'^public/task/(?P<task_pk>[^/.]+)/iframe/3d/$', public_views.model_display_iframe, name='public_iframe_3d'),
    re_path(r'^public/task/(?P<task_pk>[^/.]+)/json/$', public_views.task_json, name='public_json'),

    re_path(r'^processingnode/([\d]+)/$', app_views.processing_node, name='processing_node'),

    path('api/', include("app.api.urls")),

    re_path(r'^plugins/(?P<plugin_name>[^/.]+)/(.*)$', app_view_handler),

    path('about/', app_views.about, name='about'),
    re_path(r'^dev-tools/(?P<action>.*)$', dev_views.dev_tools, name='dev_tools'),

    # TODO: add caching: https://docs.djangoproject.com/en/5.2/topics/i18n/translation/#note-on-performance
    path('jsi18n/', JavaScriptCatalog.as_view(packages=['app']), name='javascript-catalog'),
    path('i18n/', include('django.conf.urls.i18n')),
] + root_url_patterns()

handler404 = app_views.handler404
handler500 = app_views.handler500

