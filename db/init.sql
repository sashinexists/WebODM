ALTER USER postgres PASSWORD 'postgres';

CREATE DATABASE webodm_dev;

-- Connect to webodm_dev and enable PostGIS
\c webodm_dev;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

ALTER DATABASE webodm_dev SET postgis.gdal_enabled_drivers TO 'GTiff';
ALTER DATABASE webodm_dev SET postgis.enable_outdb_rasters TO True;
