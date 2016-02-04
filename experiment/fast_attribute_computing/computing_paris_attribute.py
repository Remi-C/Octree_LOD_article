# -*- coding: utf-8 -*-
"""
Created on Thu Feb 04 17:28:45 2016

@author: RCura
"""

# -*- coding: utf-8 -*-
"""
Éditeur de Spyder

Ceci est un script temporaire.
"""

import psycopg2

def connect_to_base():
    conn = psycopg2.connect(  
        database='test_pointcloud'
        ,user='postgres'
        ,password='postgres'
        ,host='172.16.3.50'
        ,port='5432' ) 
    cur = conn.cursor()
    return conn, cur  

def execute_querry(q,arg_list,conn,cur):  
    #print q % arg_list    
    cur.execute( q ,arg_list)
    conn.commit()

#connect to database, get a list of lines to work on
#disconnect
#divide the list into chuncks

#treat a chunck with a connection, push results, close connection

def get_list_of_job(limit):
    import numpy as np
    #connect to database
    conn, cur = connect_to_base()
    #get thelist of job
    q = """ SELECT gid 
        FROM acquisition_tmob_012013.riegl_pcpatch_space
        WHERE points_per_level IS NOT NULL 
        ORDER BY gid ASC 
        LIMIT %s """ 
    execute_querry(q,[limit],conn,cur)
    gid = cur.fetchall() 
    gid = np.asarray(gid).T[0]
    cur.close()
    conn.close()
    return gid


def cut_list_into_chunk(gid, max_chunk_size):
    """ given a list , tries to cut it into smaller parts of max_chunk_size """
    import numpy as np
    import math
    result = []
    for i in np.arange(0,math.floor(gid.size/max_chunk_size)+1):
        key_local_start = int(math.ceil(i * max_chunk_size)) 
        key_local_end = int(math.trunc((i+1) * max_chunk_size))
        key_local_end = gid.size if key_local_end > gid.size else key_local_end
        extract = gid[np.arange(key_local_start,key_local_end)]
        if extract.size >0 :
            result.append(gid[np.arange(key_local_start,key_local_end)])
                
    return result

#import numpy as np
#gid = np.arange(1,100)
#cut_list_into_chunk(gid, 3)


def process_one_chunk( gid_extract  ):
    """ given a subset of the gid, do something with it"""    
    connection_string = "dbname=test_pointcloud user=postgres password=postgres host=172.16.3.50 port=5432"
    
    #create connection
    conn, cur = connect_to_base()
    #deal with the chunk 
    for i in gid_extract:
        #print('i ',i) 
        try: 
            result = process_one_gid(i,conn, cur,connection_string) 
        except: 
            err = 'error with gid : '+str(i)
            raise #NameError(err)
    #close connection
    cur.close()
    conn.close() 
        
        


def process_one_gid(one_gid, conn, cur, connection_string):
    """given one gid, process """ 
    #get data
    
    q = """ SELECT 
            COALESCE( round(PC_PatchMax(patch, 'Z')-PC_PatchMin(patch, 'Z'),3),0) AS patch_height
            ,  COALESCE( round(PC_PatchAvg(patch, 'z_origin'),3),0 ) AS height_above_laser
            , COALESCE(round(ST_Area(patch::geometry)::numeric,3),0) AS patch_area
            ,  COALESCE( round(PC_PatchAvg(patch, 'reflectance'),3),0 ) AS reflectance_avg
            ,  COALESCE( round(PC_PatchAvg(patch, 'nb_of_echo') ,3),0) AS nb_of_echo_avg
        FROM acquisition_tmob_012013.riegl_pcpatch_space 
        WHERE gid = %s   """
    arg_list = [one_gid.tolist()]
    execute_querry(q,arg_list,conn,cur)
    result =  cur.fetchall()[0] 
    return True

def printing_arglist(points_per_level, arg_list):
    print('gid of the patch')
    print(arg_list[7])
    print('cov_descriptor')
    print(arg_list[0])
    print('dim from cov descriptor')
    print(arg_list[1])
    print('LOD')
    print('points_per_level')
    print(points_per_level)
    print('theoretical_dim  : from ransac on coef')
    print(arg_list[2])  
    print('confidence on theoretical dim')
    print(arg_list[3])
    print('multiscale_dim : from lod')
    print(arg_list[4])
    print('multiscale dim : from variation of dim in lod')
    print(arg_list[5])
    print('multiscale_fused :a robust fusion of both mutliscale dim')
    print(arg_list[6])
    
    
def test_mono():
    import numpy as np
    max_chunk_size = 4
    overall_max = 10
    
    gid = get_list_of_job(overall_max)
    #print("gid : ",gid)
    gid_sequenced = cut_list_into_chunk(np.asarray(gid), max_chunk_size)
    #print('gid_sequenced ',gid_sequenced)
    for i in gid_sequenced:
        process_one_chunk(i)



def multiprocess():
    import  multiprocessing as mp; 
    import random;  
    import numpy as np
    import datetime ; 
    
    time_start = datetime.datetime.now(); 
    print 'starting : %s ' % (time_start); 
    
    processes = 8
    max_chunk_size = 10
    overall_max = 25000
    
    gid = get_list_of_job(overall_max)
    
    #print("gid : ",gid)
    gid_sequenced = cut_list_into_chunk(np.asarray(gid), max_chunk_size) 
    random.shuffle(gid_sequenced)
    print 'job in line, ready to process : %s ' % (datetime.datetime.now()); 
    #print('gid_sequenced ',gid_sequenced) 
    pool = mp.Pool(processes)
    results = pool.map(process_one_chunk, gid_sequenced)
    time_end = datetime.datetime.now(); 
    print 'ending : %s ' % (time_end); 
    print 'duration : %s ' % (time_end-time_start)
    return results
    
#test_mono()


##dirty windows trick
def main():
    multiprocess()
if __name__ == "__main__":
    main()
