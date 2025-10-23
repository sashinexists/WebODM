ALTER USER postgres PASSWORD 'postgres';
CREATE DATABASE webodm_dev;

-- Connect to webodm_dev to create extensions
\c webodm_dev

-- Create PostGIS extension (includes vector support)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create PostGIS raster extension (required for old migrations with RasterField)
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Configure PostGIS settings
ALTER DATABASE webodm_dev SET postgis.gdal_enabled_drivers TO 'GTiff';
ALTER DATABASE webodm_dev SET postgis.enable_outdb_rasters TO True;
