
-- creatng schema for experiment
CREATE SCHEMA IF NOT EXISTS lod ;
SET search_path to lod, vosges_2011, rc_lib, public; 


-- creating table with copy of data for experiment
DROP TABLE IF EXISTS las_vosges_int_lod ; 
CREATE TABLE las_vosges_int_lod (
gid INT PRIMARY KEY REFERENCES las_vosges_int(gid) , 
  file_name text,
  num_points int ,
  points_per_level integer[],
  points_per_level_py integer[],
  geom geometry(polygon,931008),
  patch pcpatch(3), 
  patch_ordered pcpatch(3)
) ;
TRUNCATE las_vosges_int_lod  ; 
INSERT INTO las_vosges_int_lod
	SELECT gid, file_name, pc_numpoints(patch),points_per_level, NULL
		,patch::geometry(polygon,931008)
		,patch
		,NULL
	FROM las_vosges_int
	WHERE gid BETWEEN 17856 AND 18856;

	
CREATE INDEX ON las_vosges_int_lod (file_name);
CREATE INDEX ON las_vosges_int_lod (num_points);
CREATE INDEX ON las_vosges_int_lod USING GIN (points_per_level);
CREATE INDEX ON las_vosges_int_lod USING GIN (points_per_level_py);
CREATE INDEX ON las_vosges_int_lod USING GIST (geom);

-- 17856;599525 


SELECT sum(num_points)
FROM las_vosges_int_lod
WHERE patch_ordered IS NOT NULL

SELECT * -- gid, points_per_level
FROM las_vosges_proxy
LIMIT 1
-------------
-- oups, the point_per_level is only computed for las_vosges, and not for las_vosges_it, transferring
-- for all geom in las_vosges_proxy, transfer points per level to las_vosges_int_proxy for patch that have the same number of points,  the same centroid

WITH to_update AS (
	SELECT lvi.gid, lv.points_per_level
	FROM las_vosges_proxy lv, las_vosges_int_proxy lvi
	WHERE ST_Intersects(lv.geom,lvi.geom) 
		AND ST_DWithin(ST_Centroid(lv.geom) , ST_Centroid(lvi.geom),0.1)
		AND lv.num_points = lvi.num_points 
)
UPDATE las_vosges_int_proxy AS lvi SET points_per_level= tu.points_per_level
FROM to_update AS tu
WHERE lvi.gid = tu.gid; 

-- transferring from proxy to lod
UPDATE las_vosges_int_lod lod SET points_per_level = lvi.points_per_level
FROM las_vosges_int_proxy lvi
WHERE lod.gid = lvi.gid ;
--------------------------

SELECT points_per_level, points_per_level_py
FROM las_vosges_int_lod
LIMIT 100

UPDATE las_vosges_int_lod
SET (points_per_level_py, patch_ordered) = (NULL,NULL) ;

-- 14 proc : 0:02:16.840000  
-- 14 process : 0:01:22

SELECT count(*), sum(num_points)  / 8.5
FROM las_vosges_int_lod
WHERE points_per_level_py IS NOT NULL 



SELECT count(*) --581529 
FROM las_vosges_proxy ; 
SELECT count(*) --581670 
FROM las_vosges_int_proxy

SELECT ST_SRID(geom)
FROM las_vosges_proxy
LIMIT 1 

SELECT  file_name
FROM las_vosges 
--1456
------------

ALTER TABLE vosges_2011.las_vosges_int_proxy ADD COLUMN points_per_level int[] ;
CREATE INDEX ON vosges_2011.las_vosges_int_proxy USING GIN(points_per_level)  ; 