from django.apps import AppConfig

class MainConfig(AppConfig):
    name = 'app'
    verbose_name = 'Application'

    def ready(self):
        """Initialize GDAL/OSR settings when the app is ready."""
        try:
            from osgeo import osr
            # Explicitly enable exceptions for GDAL 4.0 compatibility
            osr.UseExceptions()
        except ImportError:
            # GDAL not available (e.g., during tests without GIS dependencies)
            pass
