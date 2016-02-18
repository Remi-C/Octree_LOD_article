# -*- coding: utf-8 -*-
"""
Created on Tue Feb 16 21:40:11 2016

@author: remi
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
        FROM lod.dim_descr_comparison
        WHERE points_per_level IS NOT NULL
        --AND gid = 906820
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


def process_one_chunk(( nb_of_chunk, gid_modulo ) ):
    """ given a subset of the gid, do something with it"""    
    connection_string = "dbname=test_pointcloud user=postgres password=postgres host=172.16.3.50 port=5432"
    
    #create connection
    conn, cur = connect_to_base()
    #deal with the chunk 
    q = """ 
        SET SEARCH_PATH TO lod, rc_lib, public;     
        SELECT lod.rc_update_ppls_dim_lods(gid, tot_level:= 1, tot_level_broad:=3, broad_pow:=0)
        FROM lod.bench_small_cubes
        WHERE mod(gid, %s) = %s;"""
    arg_list = [nb_of_chunk, gid_modulo]
    #printing_arglist(arg_list)
    execute_querry(q,arg_list,conn,cur) 
    
    print("gid modulo ",gid_modulo ,"dealt with")
    #close connection
    cur.close()
    conn.close() 
        
        
 

def printing_arglist( arg_list):
    print('gid of the patch')
    print(arg_list[1])
    print('fast_ppl')
    print(arg_list[0]) 
    
    
def test_mono():
    import numpy as np
    nb_of_chunk = 200
    gid_modulo = 1
    process_one_chunk(( nb_of_chunk, gid_modulo ))



def multiprocess():
    import  multiprocessing as mp;  
    import numpy as np
    import datetime ; 
    
    time_start = datetime.datetime.now(); 
    print 'starting : %s ' % (time_start); 
    
    processes = 3
    nb_of_chunk = 500
    
    arg = []
    for i in np.arange(0,nb_of_chunk):
        arg.append([nb_of_chunk,i])
     
    #print("gid : ",gid)
    print 'job in line, ready to process : %s ' % (datetime.datetime.now()); 
    #print('gid_sequenced ',gid_sequenced) 
    pool = mp.Pool(processes)
    results = pool.map(process_one_chunk, arg)
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