------------------
-- Remi Cura, Thales IGN 2016
--testing halton sequence generator
------------------


SET search_path to lod_low_disc, rc_lib, public; 


DROP TABLE IF EXISTS test_halton ; 
CREATE TABLE test_halton AS  

WITH to_keep AS (
	SELECT (row_number() over(ORDER BY ordering) )::int AS gid, val[1] AS x, val[2] AS y  
		,ST_SetSRID(ST_MakePoint(val[1],val[2]),931008)::geometry(point,931008) AS point
	FROM  rc_generate_Halton_seq(2,1000)
	WHERE ordering > 100 
)
SELECT   gid,   x,   y  , point
	, CASE WHEN pow = 0 then 1 else pow END AS pow
FROM to_keep, ceiling(ln(gid )/ln(4)) AS pow  ; 

CREATE INDEX ON test_halton USING GIST (point) ; 



DROP FUNCTION IF EXISTS rc_order_by_Halton (points_gid int[]  , points_to_order geometry, max_nb_point_to_order int );
CREATE FUNCTION rc_order_by_Halton ( points_gid int[]  , points_to_order geometry, max_nb_point_to_order int
	) 
RETURNS  TABLE(point_gid int, ordering int )   
AS $$
"""
This function takes a set of point and order them according to who is closer to successive hamilton seq values
"""
#importing needed modules
import ghalton
from rtree import index
from shapely import wkb ; #loading geometry from postgres
from shapely.geometry import asMultiPoint
import plpy  
import numpy as np
from math import log

#getting the points from the multipoint we have
geom = wkb.loads( points_to_order, hex=True ) ;
p = np.asarray(geom)  #putting the geom into an array
gid = np.asarray(points_gid)   
nb_of_dim = p.shape[1]
nb_of_point = p.shape[0]
eps = 10^-9

#constructing a RTree with the points
prop = index.Property()

prop.interleaved = False
prop.dimension = 3 

prop.leaf_capacity = int(1+ log(nb_of_point)) 
prop.index_capacity = nb_of_point*2
prop.near_minimum_overlap_factor = min(prop.near_minimum_overlap_factor, prop.leaf_capacity)


idx3d = index.Index(properties=prop)
for i,point in enumerate(p): 
	idx3d.insert(i, ( point[0], point[1]  , point[2] ) )


#for i,point in enumerate(p): 
#	idx3d.delete(i, ( point[0], point[1]  , point[2] ) ) 


#finding the points lower and upper bound (to deduce translation and scaling)
amin = np.amin(p.T, axis=1)
amax= np.amax(p.T, axis=1)
translate = amin
scale = amax-amin
  

#constructing the Halton sequence we will need
sequencer = ghalton.Halton(nb_of_dim) 
halt = sequencer.get(min(nb_of_point,max_nb_point_to_order))* scale+translate
 
result = list() 
#loop on points to find the closest one to hamilton seq
for i,seq in enumerate(halt):
	#loop on halton sequence
	#find closes point 
	closest_pt_idx = np.asarray(list(idx3d.nearest((seq[0],seq[1],seq[2]), 1)))
	closest_pt_idx = closest_pt_idx[0] 
	closest_pt = p[closest_pt_idx,:]
	result.append((gid[closest_pt_idx],i)) 
	
	#remove this point from index
	idx3d.delete(closest_pt_idx 
		,  (p[closest_pt_idx,0],p[closest_pt_idx,1],p[closest_pt_idx,2])
	)

#for i  in range(0, nb_of_point):  
#       result.append((i, p[i]))
return result 
  
$$ LANGUAGE plpythonu IMMUTABLE STRICT; 





WITH points AS (
	SELECT row_number() over() as gid,  s1,s2,s3, St_MakePoint(s1,s2,s3) AS point
	FROM generate_series(1,5) AS s1
		,generate_series(1,5) AS s2
		,generate_series(1,5) AS s3
)
, preparing_data AS (
	SELECT array_agg(gid::int ORDER BY gid) AS gids, ST_Collect(point ORDER BY gid) AS points
	FROM points
)
SELECT f.* 
FROM preparing_data, rc_order_by_Halton(gids, points, 1000) AS f  ;


-----------
-- testing hamilton sequence on real point cloud
-----------

SELECT count(*)
FROM tmob_20140616.lens_points
-- 5918193

-- exporting points for visu in ccompare
COPY(
	SELECT  X, Y, Z , tid, attributes::float AS reflectance
	FROM ST_SetSRID(ST_MAkePoint(650907.6841,6861141.0047),931008 ) as ref_point
		, tmob_20140616.lens_points ,ST_Transform(point,932011) AS pt,   ST_X(pt) AS X, ST_y(pt) AS y, ST_z(pt) AS Z
	WHERE ST_DWithin(point, ref_point,3)  
	--AND
	--ORDER BY ST_X(point)^2 +ST_y(point)^2 + ST_z(point)^2
	--LIMIT 1000

) TO '/ExportPointCloud/visu_lens_points_full.csv' WITH CSV HEADER

--using hamilton sequ
WITH points AS (
	SELECT count*) --  tid AS gid, ST_Transform(point,932011) As point
	FROM ST_SetSRID(ST_MAkePoint(650907.6841,6861141.0047),931008 ) as ref_point, 
		tmob_20140616.lens_points 
	WHERE ST_DWithin(point, ref_point,0.5)  
	--ORDER BY ST_X(point)^2 +ST_y(point)^2 + ST_z(point)^2
	--LIMIT 1000 
)
, preparing_data AS (
	SELECT array_agg(gid::int ORDER BY gid) AS gids, ST_Collect(point ORDER BY gid) AS points
	FROM points
)
SELECT f.* 
FROM preparing_data, rc_order_by_Halton(gids, points, 120000) AS f  ;