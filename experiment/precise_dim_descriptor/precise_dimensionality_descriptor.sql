--------------------
-- Remi Cura, IGN, Thales, 2016
---------------------

-- setting search path
SET search_path to lod, benchmark_cassette_2013, rc_lib, public;

--creating a function that splits a patch in cubes  = patch_size / 2^N
DROP FUNCTION IF EXISTS rc_split_patch_in_2_pow_N(pcpatch , int) ; 
CREATE OR REPLACE FUNCTION rc_split_patch_in_2_pow_N(   IN ipatch pcpatch , IN pow_splitting int   ) 
RETURNS SETOF pcpatch  AS
$BODY$ /** given a patch, split it into smaller patch, new patch wide being old_patch_wide/2^pow_splitting*/
	DECLARE    
	BEGIN  
		RETUrN QUERY
		WITH points AS (
			SELECT *
			FROM pc_explode(ipatch) as pt, CAST(pt AS geometry) AS point, st_x(point) as x, st_y(point) as y, st_z(point) as z  
		)
		--, patches AS (
			SELECT pc_patch(pt) as n_patch
			FROM points
			GROUP BY floor(pow(2,pow_splitting) * x), floor(pow(2,pow_splitting)* y ), floor(pow(2,pow_splitting) * z )  ;
		RETURN ; 
	END ;
	$BODY$
LANGUAGE plpgsql IMMUTABLE STRICT; 

-- creating a new table with a copy of the data
DROP TABLE IF EXISTS bench_small_cubes;
CREATE TABLE bench_small_cubes(
gid serial primary key 
, old_gid int references benchmark_cassette_2013.riegl_pcpatch_space (gid)
, num_points float
, points_per_level int[] --classical ppl for the points in the patch
, points_per_level_broad int[] --calculated by considering all patch in a 1 m cube , only 3 levels
, dim_loddiff float[] -- computed by doing ln(ppl[i+i]/ppl[i])/ln(2)
, dim_loddiff_broad float[] -- computed by doing ln(ppl[i+i]/ppl[i])/ln(2)
, centroid geometry(pointZ,932011) -- this is the centroid of the octree cell, that is the rounded centroid
, patch_geom geometry(polygon,932011)
, patch PCPATCH(6) -- a small patch
) ; 
CREATE INDEX ON bench_small_cubes (old_gid) ; 
CREATE INDEX ON bench_small_cubes (num_points) ; 
CREATE INDEX ON bench_small_cubes (points_per_level) ; 
CREATE INDEX ON bench_small_cubes (points_per_level_broad) ; 
CREATE INDEX ON bench_small_cubes (dim_loddiff) ; 
CREATE INDEX ON bench_small_cubes (dim_loddiff_broad) ; 
CREATE INDEX ON bench_small_cubes USING GIST (centroid gist_geometry_ops_nd) ; 
CREATE INDEX ON bench_small_cubes USING GIST (patch_geom  ) ; 
CREATE INDEX ON bench_small_cubes USING GIST (CAST(patch AS geometry ) gist_geometry_ops_nd) ; 

-- filling the table by splitting the original 1m patch into 1/8 m patches
TRUNCATE bench_small_cubes ;
INSERT INTO bench_small_cubes (gid, old_gid, num_points, points_per_level,points_per_level_broad,dim_loddiff, centroid,patch_geom, patch)
SELECT row_number() over(), gid ,pc_numPoints(npatch), NULL, NULL, NULL,
	ST_Translate( ST_SetSRID(ST_MakePoint(floor(ST_X(ct3D) * pow(2,3) ) / pow(2,3)
		,floor(ST_Y(ct3D) * pow(2,3) ) / pow(2,3)
		,floor(ST_Z(ct3D) *  pow(2,3) ) /  pow(2,3)
		),ST_SRID(ct3D))
		, 1/pow(2,4),1/pow(2,4),1/pow(2,4))
	, CASE WHEN PC_NUmPoints(npatch)<=2 THEN ST_SetSRID(Box2D(ST_Buffer(npatch::geometry,0.025)),ST_SRID(ct))
	ELSE npatch::geometry END
	, npatch   
FROM riegl_pcpatch_space  , ST_GeomFromText('POINT(1894.09 21297.91)',932011) AS ref_point, rc_split_patch_in_2_pow_N(patch,3) as npatch  
	,ST_Centroid(npatch::geometry) as ct, St_SetSRID(ST_MakePoint(st_x(ct),st_y(ct), Pc_PatchAvg(patch,'Z')), ST_SRID(ct)) as ct3D
	WHERE ST_DWIthin(patch::geometry, ref_point, 5)  
	AND gid % 5 = 0 ;



--example of query to get the patch centroid who belong ot the same 1m wide octree cell (aka reaching upper)
	-- use custom function

	--creating a function that finds centroid in the upper level of the octree
DROP FUNCTION IF EXISTS rc_find_centroids_upper_levels(icentroid geometry , int) ; 
CREATE OR REPLACE FUNCTION rc_find_centroids_upper_levels(  icentroid geometry, IN pow_octree int  , OUT cells_center geometry ) 
RETURNS geometry  AS
$BODY$ /** given points, looks for those in the same octree cell of wideth 2^pow_octree*/
	DECLARE    
	BEGIN  
		 WITH input_data AS(
		SELECT  icentroid,   pow(2,pow_octree-1) AS threshold  
	 )
	--  ,pre_filtering AS ( -- spatial filtering with 3D index, result is broader than the expected
	SELECT ST_Collect(centroid) INTO cells_center
	FROM input_data AS id, bench_small_cubes
	WHERE ST_3DDwithin(id.icentroid, centroid,sqrt(3*threshold ) )
		-- reducing the power by 1 because 3DDIstance consider radius and not diametre
			AND abs(ST_X(id.icentroid) - ST_X(centroid)) <= threshold
			AND abs(ST_Y(id.icentroid) - ST_Y(centroid)) <= threshold
			AND abs(ST_Z(id.icentroid) - ST_Z(centroid)) <= threshold ; 
		RETURN ; 
	END ;
	$BODY$
LANGUAGE plpgsql IMMUTABLE STRICT; 

DROP TABLE IF EXISTS test;
CREATE TABLE test AS 
	SELECT row_number() over() as gid, f.cells_center::geometry(multipointZ,932011)
	FROM bench_small_cubes , 
		rc_find_centroids_upper_levels( centroid, 0) AS f 
	WHERE gid = 7359;  


 
--filling points_per_level , and points_per_level_broad (completed with points_per_level)
 -- array_append(points_per_level_broad[1-4], points_per_level) 
-- computing descriptor

WITH to_update AS (
	SELECT gid, ppl_, centroids, ppl_broad_
		 , dim_loddiff_.dim_loddiff  AS dim_loddiff__
		 , dim_loddiff_broad_.dim_loddiff AS dim_loddiff_broad__
	FROM bench_small_cubes AS bsc
		, rc_lib.rc_patch_to_ppl (pc_uncompress(bsc.patch), 3 ) as ppl_
		, rc_find_centroids_upper_levels(bsc.centroid , 0) AS centroids
		, rc_lib.rc_multipoints_to_ppl ( centroids, 3) AS  ppl_broad_
		 , rc_lib.rc_ppl_to_dim_feature (ppl_,   ppl_[array_length(ppl_, 1)] )  as dim_loddiff_
		  ,  rc_lib.rc_ppl_to_dim_feature (ppl_broad_, ppl_broad_[array_length(ppl_broad_, 1)] )  as dim_loddiff_broad_
	WHERE bsc.gid = 7359
)
UPDATE bench_small_cubes AS bsc SET (  points_per_level  , points_per_level_broad  , dim_loddiff , dim_loddiff_broad )
 = (ppl_, ppl_broad_, dim_loddiff__, dim_loddiff_broad__) 
FROM  to_update AS tu
WHERE bsc.gid = tu.gid  ;


	--creating a function that finds centroid in the upper level of the octree
DROP FUNCTION IF EXISTS rc_update_ppls_dim_lods(gid_to_update int, tot_level int ,tot_level_broad int ,  broad_pow int  ) ; 
CREATE OR REPLACE FUNCTION rc_update_ppls_dim_lods(gid_to_update int, tot_level int DEFAULT 2, tot_level_broad int  DEFAULT 3 , broad_pow int DEFAULT 0)
RETURNS VOID  AS
$BODY$ /** given a gid, compute ppl, ppl_broad, dim_loddiff, dim_loddiff_broad*/
	DECLARE    
	BEGIN  
	WITH to_update AS (
		SELECT gid, ppl_, centroids, ppl_broad_
			 , dim_loddiff_.dim_loddiff  AS dim_loddiff__
			 , dim_loddiff_broad_.dim_loddiff AS dim_loddiff_broad__
		FROM bench_small_cubes AS bsc
			, rc_lib.rc_patch_to_ppl (pc_uncompress(bsc.patch), tot_level ) as ppl_
			, rc_find_centroids_upper_levels(bsc.centroid , broad_pow) AS centroids
			, rc_lib.rc_multipoints_to_ppl ( centroids, tot_level_broad) AS  ppl_broad_
			 , rc_lib.rc_ppl_to_dim_feature (ppl_,   ppl_[array_length(ppl_, 1)] )  as dim_loddiff_
			  ,  rc_lib.rc_ppl_to_dim_feature (ppl_broad_, ppl_broad_[array_length(ppl_broad_, 1)] )  as dim_loddiff_broad_
		WHERE bsc.gid = gid_to_update
	)
	UPDATE bench_small_cubes AS bsc SET (  points_per_level  , points_per_level_broad  , dim_loddiff , dim_loddiff_broad )
	= (ppl_, ppl_broad_, dim_loddiff__, dim_loddiff_broad__) 
	FROM  to_update AS tu
	WHERE bsc.gid = tu.gid  ;
	RETURN  ; 
	END ;
	$BODY$
LANGUAGE plpgsql VOLATILE STRICT; 
  
	
SELECT rc_update_ppls_dim_lods(gid, tot_level:= 1, tot_level_broad:=3, broad_pow:=0)
FROM bench_small_cubes
WHERE gid % 20   = 0 ;


COPY (
	SELECT round(st_x(pt),3) AS x, round(st_y(pt),3) AS y, round(st_z(pt),3) AS z, old_gid, gid,
		dim_loddiff_broad[1] as dim1,dim_loddiff_broad[2] dim2 ,dim_loddiff_broad[3] dim3, dim_loddiff[1] dim01
	FROM bench_small_cubes, pc_explode(patch) as point, CAST(point AS GEOMETRY) AS pt
	WHERE dim_loddiff_broad IS NOT NULL
	--LIMIT 100000
) TO '/media/sf_USB_storage/PROJETS/Article_biblio/Octree_LOD/experiment/precise_dim_descriptor/pointcloud_dim_descr_tot.csv'
WITH HEADER CSV; 
 