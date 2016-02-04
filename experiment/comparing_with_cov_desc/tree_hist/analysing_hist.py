# -*- coding: utf-8 -*-
"""
Created on Thu Feb 04 11:22:52 2016

@author: RCura
reading both histogramm from cloud compare
smoothing and outputting in the same figure
"""
import numpy as np
import matplotlib.pyplot as plt 
from scipy import stats

pts = np.genfromtxt(
    'full_tree.csv',           # file name
    skip_header=0,          # lines to skip at the top
    skip_footer=0,          # lines to skip at the bottom
    delimiter=';',          # column delimiter
    dtype='float32',        # data type
    filling_values=0,       # fill missing values with 0
    #usecols = (0,2,3,5),    # columns to read
    names=True)     # column names
                        
#X;Y;Z;R;G;B;gid;p_1;p_2;p_3;dim_cov;dim_the;dim_lod_all;dim_lod_m_dim_conf
#print pts

#hist_cov,sup_cov = np.histogram(pts['dim_cov'])
#hist_lod,sup_lod = np.histogram(pts['dim_lod_all']) 
for dim in ['dim_cov','dim_lod_all']:
    pts_unique =  pts[dim]#np.unique(pts[dim])
    kernel = stats.gaussian_kde(pts_unique,0.15)
    min = np.min(pts[dim])
    max = np.max(pts[dim])
    linsp = np.linspace(min, max,200)
    #print kernel( linsp) 
    plt.plot(linsp,kernel(linsp))
    plt.show()
  
