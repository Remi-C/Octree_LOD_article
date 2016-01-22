------------------
-- Remi Cura, Thales IGN 2016
--testing halton sequence generator
------------------


SET search_path to lod_low_disc, rc_lib, public; 

/*


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



DROP FUNCTION IF EXISTS rc_order_by_Halton (points_gid int[]  , points_to_order geometry, max_nb_point_to_order int , dim int);
CREATE FUNCTION rc_order_by_Halton ( points_gid int[]  , points_to_order geometry, max_nb_point_to_order int, dim int DEFAULT NULL
	) 
RETURNS  TABLE(point_gid int, ordering int )   
AS $$ 
#This function takes a set of point and order them according to who is closer to successive hamilton seq values 
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
if dim !=2 and dim !=3:
	nb_of_dim = p.shape[1]
else:
	nb_of_dim = dim

nb_of_point = p.shape[0] 
p = p[:,0:nb_of_dim]
   
#constructing a RTree with the points
prop = index.Property()

prop.interleaved = False
prop.dimension = dim 

prop.leaf_capacity = int(1+ log(nb_of_point)) 
prop.index_capacity = nb_of_point*2
prop.near_minimum_overlap_factor = min(prop.near_minimum_overlap_factor, prop.leaf_capacity)


idx3d = index.Index(properties=prop)
for i,point in enumerate(p): 
	if nb_of_dim == 3: 
		idx3d.insert(i, ( point[0], point[1]  , point[2] ) )
	else:
		idx3d.insert(i, ( point[0], point[1]  ) )

#finding the points lower and upper bound (to deduce translation and scaling)
amin = np.amin(p.T, axis=1)
amax= np.amax(p.T, axis=1)
translate = amin
scale = amax-amin
  

#constructing the Halton sequence we will need
sequencer = ghalton.GeneralizedHalton(nb_of_dim,100) 
halt = sequencer.get(min(nb_of_point,max_nb_point_to_order))* scale+translate
 
result = list() 
#loop on points to find the closest one to hamilton seq
for i,seq in enumerate(halt):
	#loop on halton sequence
	#find closes point 
	if nb_of_dim == 3: 
		closest_pt_idx = np.asarray(list(idx3d.nearest((seq[0],seq[1],seq[2]), 1)))
	else:
		closest_pt_idx = np.asarray(list(idx3d.nearest((seq[0],seq[1]), 1)))
	closest_pt_idx = closest_pt_idx[0] 
	closest_pt = p[closest_pt_idx,:]
	result.append((gid[closest_pt_idx],i)) 
	
	#remove this point from index
	if nb_of_dim == 3: 
		idx3d.delete(closest_pt_idx  ,  (p[closest_pt_idx,0],p[closest_pt_idx,1],p[closest_pt_idx,2]) )
	else:
		idx3d.delete(closest_pt_idx  ,  (p[closest_pt_idx,0],p[closest_pt_idx,1]) )

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
	SELECT    tid AS gid, ST_Transform(point,932011) As point
	FROM ST_SetSRID(ST_MAkePoint(650907.6841,6861141.0047),931008 ) as ref_point, 
		tmob_20140616.lens_points 
	WHERE ST_DWithin(point, ref_point,0.5)  
	--ORDER BY ST_X(point)^2 +ST_y(point)^2 + ST_z(point)^2
	LIMIT 1000 
)
, preparing_data AS (
	SELECT array_agg(gid::int ORDER BY gid) AS gids, ST_Collect(point ORDER BY gid) AS points
	FROM points
)
SELECT f.* 
FROM preparing_data, rc_order_by_Halton(gids, points, 1000) AS f  ;

-------------
-- for illustration : creating a table with few points, ordering following halton, random, inverse morton
-----------

DROP TABLE IF EXISTS comparison_ordering ; 
CREATE TABLE comparison_ordering (
	gid serial primary key
	, geom geometry(point,0)
	,basic_ordering int
	,random_ordering int
	,halton_ordering int
	,inv_hilbert_ordering int
)






DROP FUNCTION IF EXISTS rc_XY_to_Hilbert(INOUT gid bigint,IN x int,IN y int ,IN square_size int, OUT hilbert_code int);
CREATE OR REPLACE FUNCTION rc_XY_to_Hilbert(INOUT gid bigint,IN x int,IN y int ,IN square_size int, OUT hilbert_code int) 
AS
$BODY$
-- this function convert (X,Y) coordinates into a Hilbert code
-- square n by n cells, x y are int and coordinate within this square
-- xy from 0 to n-1
DECLARE
	n int := square_size ; 
	rx int := 0;
	ry int := 0 ;
	s int := 0 ;
	d int := 0 ;  
	_useless record;  
BEGIN
	s := n/2; 
	WHILE s >0 LOOP
		
		rx := ((x & s) > 0)::int;
		ry := ((y & s) > 0)::int;
		d := d + s * s * ((3 * rx) # ry); 
		_useless := rc_XY_to_Hilbert_rotate(s, x, y, rx, ry);
		s := s/2 ; 
	END LOOP ;
	hilbert_code := d ; 
    RETURN;  
	RETURN;	
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
 

  
DROP FUNCTION IF EXISTS rc_XY_to_Hilbert_rotate(IN n int ,INOUT x int,INOUT y int ,IN rx int, IN ry INT);
CREATE OR REPLACE FUNCTION rc_XY_to_Hilbert_rotate(IN n int ,INOUT x int,INOUT y int ,IN rx int, IN ry INT) 
AS
$BODY$
-- this function convert (X,Y) coordinates into a Hilbert code
-- square n by n cells, x y are int and coordinate within this square
-- xy from 0 to n-1
DECLARE 
	_t int ; 
BEGIN 
		IF ry = 0 THEN
			IF rx = 1 THEN
				x := n - 1 - x;
				y := n - 1 - y;
			END IF; 
			-- Swap x and y
			_t := x ;
			x := y ;
			y := _t ;
		END IF ; 
	RETURN;	
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;

DROP FUNCTION IF EXISTS rc_inverse_interleaving( X int, Y int,n_bit int);
CREATE OR REPLACE FUNCTION rc_inverse_interleaving( X int, Y int,  n_bit int, OUT interleaved text,OUT r_interleaved text ) 
AS
$BODY$
--  use X Y, interleave the bits , revert it
-- nbit xcan be computed like this : GREATEST(ceiling(ln(X)/ln(2))+1,ceiling(ln(Y)/ln(2))+1)
DECLARE   
	_x_b text ;
	_y_b text ;
	_x_a text[] ;
	_y_a text[];
	_q text;  
	_inter text[] ;
BEGIN 
	--converting both coordinates to bit
	_q :=  format('SELECT $1::bit(%s)::text,$2::bit(%s)::text',n_bit,n_bit) ; 
	EXECUTE _q INTO _x_b, _y_b USING X,Y; 

	_x_a := string_to_array(_x_b,NULL) ; 
	_y_a := string_to_array(_y_b,NULL) ; 

	--RAISE NOTICE '% % ', _x_a, _y_a ;  
	
	FOR _i in 1 .. n_bit LOOP
		IF _inter IS NULL THEN
			_inter :=  ARRAY[_x_a[_i]] || _y_a[_i]  ;
		ELSE
			_inter :=  _inter ||_x_a[_i] || _y_a[_i]  ; 
		END IF ;  
	END LOOP ; 
	interleaved := array_to_string(_inter,'') ;  
	r_interleaved := reverse(interleaved) 
	 RETURN ; 
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
 
  SELECT f.*
  FROM  rc_inverse_interleaving(12,11,5) AS f ; 
 

  SELECT ceiling(ln(64)/ln(2))
  SELECT 64::bit(7)

*/
	 
	DROP TABLE IF EXISTS various_ordering ; 
	CREATE TABLE various_ordering AS 
	WITH points AS (
		SELECT row_number() over() as gid,  s1,s2 --,s3
			--, St_MakePoint(s1,s2,s3) AS point
			, St_MakePoint(s1,s2) AS point
			, random( ) AS rand
		FROM generate_series(0,15) AS s1
			,generate_series(0,15) AS s2 
	 
	)
	, preparing_data AS (
		SELECT array_agg(gid::int ORDER BY gid) AS gids, ST_Collect(point ORDER BY gid) AS points
		FROM points
	)
	 ,hamilton_ordering AS (
		SELECT f.point_gid AS gid, f.ordering AS hatlon_ordering
		FROM preparing_data, rc_order_by_Halton(gids, points, 256,2) AS f  
	)
	 , rand_ordering AS (
		SELECT gid, row_number() over(order by rand) AS rand_ordering
		FROM points
	)
	, z_curve_ordering AS (
		SELECT gid, row_number() over(ORDER BY f.r_interleaved) AS z_ordering
		FROM points, rc_inverse_interleaving((4+s1)%16,(4+s2)%16,6) AS f
	)
	 , results AS (
		SELECT f.gid, s1 AS X, s2 AS Y,  point AS point
			, ST_SetSRID(ST_MakePoint(s1+random()/4.0,s2+random()/4.0),0) as r_point,  f.hilbert_code
			, f.hilbert_code::bit(6) AS hilbert_code_binary
			, reverse(((0+f.hilbert_code)    )::bit(8)::text) AS hilbert_code_binary_reverted 
		FROM points 
			, rc_XY_to_Hilbert( gid,x:=( 4+ s1)%16 ,y:=(4+ s2)%16 ,square_size:=16) AS f
	)
	 , revert_hilbert_ordering AS (
		SELECT gid, row_number() over(order by hilbert_code_binary_reverted) AS r_hilbert_ordering
		FROM results
	)
	SELECT r.gid, r.X, r.Y, r.point::geometry(point,0) , r.r_point::geometry(point,0) 
		, ho.hatlon_ordering, ro.rand_ordering, rh.r_hilbert_ordering 
		, zc.z_ordering
	FROM results AS r 
		LEFT OUTER JOIN hamilton_ordering AS ho USING (gid) 
		LEFT OUTER JOIN rand_ordering AS ro USING (gid) 
		LEFT OUTER JOIN revert_hilbert_ordering AS rh USING (gid)  
		LEFT OUTER JOIN z_curve_ordering AS zc USING (gid) 
 
	