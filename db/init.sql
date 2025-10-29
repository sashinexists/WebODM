ALTER USER postgres PASSWORD 'postgres';
CREATE DATABASE webodm_dev;

-- Connect to webodm_dev to enable extensions
\c webodm_dev

-- Enable PostGIS extensions (required for PostgreSQL 14+)
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Configure PostGIS settings
ALTER DATABASE webodm_dev SET postgis.gdal_enabled_drivers TO 'GTiff';
ALTER DATABASE webodm_dev SET postgis.enable_outdb_rasters TO True;
