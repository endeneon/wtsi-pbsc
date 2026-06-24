import pysam
import pybedtools
import numpy as np
import math

import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)

import pandas as pd
import argparse


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Process BAM files and generate suggested splits for a specified chromosome."
    )

    parser.add_argument(
        "-c", "--chunks",
        dest="chunks",
        type=int,
        required=True,
        help="The number of chunks to divide the data into. Has to be a power of 2. Example: 2,4,8,16..."
    )

    parser.add_argument(
        "-b", "--bam-fofn",
        dest="bam_fofn",
        type=str,
        required=True,
        help="Path to the file of filenames containing BAM file paths. Example: 'bam.fofn'"
    )

    parser.add_argument(
        "-o", "--output-file",
        dest="output_f",
        type=str,
        required=True,
        help="Path to the output BED file to save the suggested splits. Example: 'suggested_splits.bed'"
    )

    parser.add_argument(
        "-s", "--bed-f",
        dest="bed_f",
        type=str,
        required=True,
        help="Path to the BED file containing split points. Example: 'split_points.bed'"
    )
    parser.add_argument(
        "-z", "--chrom-sizes-f",
        dest="chrom_sizes_f",
        type=str,
        required=True,
        help="Chromosome sizes file. Provided in data/"
    )

    parser.add_argument(
        "-r", "--chrom",
        dest="chrom",
        type=str,
        required=True,
        help="The chromosome to process. Example: 'chr1'"
    )

    return parser.parse_args()



def compute_readcount_ratio(splitpoint_readcount):
    readcount_ratio=(splitpoint_readcount[1]+0.01)/(splitpoint_readcount[2]+0.01)
    if readcount_ratio < 1:
        readcount_ratio=1/readcount_ratio
    return readcount_ratio

def compute_bam_counts(bam_files,s,e,region):
    """
    Takes a region and computes the number of nodes within, to its left and to its right (within a wider region s-e)
    """
    region_chr,region_s,region_e=region

    allsample_total_counts_within = 0
    allsample_total_counts_right  = 0
    allsample_total_counts_left   = 0
    #this is to handle the very edge case of region boundaries lying beyond the the initial splitpoints (median)

    if (region_e > e) or (region_s < s):
        print("Invalid region: {region_chr}:{region_s}-{region_e}. Must be within {s}-{e}.".format(region_chr=region_chr,region_s=region_s,region_e=region_e,s=s,e=e),flush=True)
        region_s=max(region_s,s)
        region_e=min(region_e,e)
        print("Adjusting region start and end points to {region_chr}:{region_s}-{region_e}".format(region_chr=region_chr,region_s=region_s,region_e=region_e),flush=True)
    assert (region_e <= e) and (region_s >= s), "Invalid region: {region_chr}:{region_s}-{region_e}. Must be within {s}-{e}".format(region_chr=region_chr,region_s=region_s,region_e=region_e,s=s,e=e)
    for bam_full_path in bam_files:
        with pysam.AlignmentFile(bam_full_path, "rb") as bam:
            allsample_total_counts_within+=bam.count(region_chr,region_s,region_e)
            allsample_total_counts_left+=bam.count(region_chr,s,region_s)
            allsample_total_counts_right+=bam.count(region_chr,region_e,e)
    counts=[allsample_total_counts_within,allsample_total_counts_left,allsample_total_counts_right]
    return(counts)

def binary_search_regions(bam_files,bed,chrom,s,e,tested_regions=None):
    """
    Takes a list of valid splitpoints (bed) and performs a binary search and reports valid splitpoints at each level of the binary search tree
    """
    bed=bed.loc[bed[0]==chrom,:]
    #TODO: define midpoint based on actual zero-coverage regions rather than median
    midpoint=np.median(bed[1])
    bed.loc[:,'dist_to_midpoint']=np.abs(bed[1]-midpoint)
    bed=bed.sort_values(by=['dist_to_midpoint']).reset_index(drop=True)
    region=bed.iloc[0,:]
    counts=compute_bam_counts(bam_files,s,e,[chrom,region[1],region[2]])
    new_tested_region=pd.DataFrame({0:[region[0]],1:[region[1]],2:[region[2]],'count_with':counts[0],'count_left':counts[1],'count_right':counts[2]  })

    #If this is the head of the tree, create new dataframe
    if tested_regions is None:
        tested_regions=pd.DataFrame(new_tested_region)
    else:
        tested_regions=pd.concat([tested_regions,new_tested_region],ignore_index=True)
    #Termination condition: If this is the last node of the tree, return else the function shifts to the left/right and tests children nodes
    if bed.shape[0] == 1:
        return tested_regions

    #Prpraing regions to be tested in further nodes
    ## if counts on the right are more, supply regions that are further to the right
    if counts[2] > counts[1]:
        if bed.loc[bed[1] > midpoint,:].shape[0] > 0:
            bed=bed.loc[bed[1] > midpoint,:]
        ###If there are no regions to the right then this region is the best splitpoint
        else:
            bed=bed.iloc[[0],:]
    ## opposite logic if counts are more to the left
    else:
        if bed.loc[bed[1] < midpoint,:].shape[0] > 0:
            bed=bed.loc[bed[1] < midpoint,:]
        else:
            bed=bed.iloc[[0],:]
    #one more iteration down the tree
    return binary_search_regions(bam_files,bed,chrom,s,e,tested_regions)

def traverse_bintree(splitpoints,nth=1):
    """
    Takes regions output from binary_search_regions and finds the best splitpoint based on the ratio between numreads to the left and right of each splitpoint
    """
    splitpoints['readcount_ratio']=splitpoints['count_left']/splitpoints['count_right']
    splitpoints.loc[splitpoints['readcount_ratio'] < 1,'readcount_ratio']=1/splitpoints.loc[splitpoints['readcount_ratio'] < 1,'readcount_ratio']
    splitpoints=splitpoints.sort_values(['readcount_ratio'],ascending=True).reset_index(drop=True)
    return splitpoints.iloc[nth-1,:]
def split_chr(bed,bam_files,chrom,s,e,iters=2,curr_iter=0):
    bed=bed.loc[bed[0]==chrom,:]

    #Termination condition: if current iteration is the last
    if curr_iter == iters:
        return []

    #Find the best splitpoint at this iteration
    splitpoints=binary_search_regions(bam_files,bed,chrom,s,e)

    #Continuing down the iterations:
    nth=1
    not_optimal=False
    required_on_side=(2**(iters-curr_iter) ) - 1
    print('Iteration {i}: {s}-{e}'.format(i=curr_iter,s=s,e=e),flush=True)
    best_splitpoint=traverse_bintree(splitpoints,nth=nth)
    bed_before_s = bed.loc[(bed[1] > s) & (bed[2] < best_splitpoint[1]) ,:]
    bed_after_e  = bed.loc[(bed[1] > best_splitpoint[2]) & (bed[2] < e) ,:]

    while (bed_before_s.shape[0] < required_on_side) or (bed_after_e.shape[0] < required_on_side):
        not_optimal=True
        nth+=1
        best_splitpoint=traverse_bintree(splitpoints,nth=nth)
        bed_before_s = bed.loc[(bed[1] > s) & (bed[2] < best_splitpoint[1]) ,:]
        bed_after_e  = bed.loc[(bed[1] > best_splitpoint[2]) & (bed[2] < e) ,:]
    if not_optimal:
        print("WARNING: there aren't enough splitpoints on either side of the optimal splitpoint ({n} splitpoints). Chosen split point was the {nth}th best".format(nth=nth,n=required_on_side),flush=True)
        print(splitpoints.sort_values(by=['readcount_ratio'],ascending=True),flush=True)

    print('Best split-point:{pc}:{ps}-{pe}. Counts on left,within,right: {left},{within},{right}. Chunks count ratio: {ratio} .'.format(pc=best_splitpoint[0],ps=best_splitpoint[1],pe=best_splitpoint[2],left=best_splitpoint['count_left'],  within=best_splitpoint['count_with'],right=best_splitpoint['count_right'],ratio=best_splitpoint['readcount_ratio']),flush=True)
    print('-------',flush=True)


    ##if nothing is left to the left of the best splitpoint, perform further splits to the right
    if (bed_before_s.shape[0]==0) and (bed_after_e.shape[0] > 0):
        return [[s,best_splitpoint[1]],[best_splitpoint[2],e]] + split_chr(bed_after_e,bam_files,chrom,best_splitpoint[2],e,iters,curr_iter+1)
    ##if nothing is left to the right of the best splitpoint, perform further splits to the left
    elif (bed_before_s.shape[0]>0) and (bed_after_e.shape[0]==0):
        return [[s,best_splitpoint[1]],[best_splitpoint[2],e]] +  split_chr(bed_before_s,bam_files,chrom,s,best_splitpoint[1],iters,curr_iter+1)
    ##if nothing is left to the left or right of the best splitpoint, return (this could possibly provide less splits than asked by the user)
    elif (bed_before_s.shape[0]==0) and (bed_after_e.shape[0]==0):
        print("WARNING: you don't have enough splitpoints to perform optimal splitting. Returning {chunks} chunks only".format(chunks=(current_iter+1)*2 ),flush=True)
        return [[s,best_splitpoint[1]],[best_splitpoint[2],e]]
    ##if there are points to the left and right
    return [[s,best_splitpoint[1]],[best_splitpoint[2],e]]  + split_chr(bed_before_s,bam_files,chrom,s,best_splitpoint[1],iters,curr_iter+1) + split_chr(bed_after_e,bam_files,chrom,best_splitpoint[2],e,iters,curr_iter+1)

def merge_splits(splits):
    left_borders = sorted(list(set([split[0] for split in splits]) ))
    right_borders= sorted(list(set([split[1] for split in splits]) ))
    split_intervals=[[l,r] for l,r in zip(left_borders,right_borders)]
    return split_intervals

###########
#Arguemnts#
###########
chunks=16
bam_fofn=None
output_f = None
bed_f=None
chrom_sizes_f=None
chrom = "chr1"

args=parse_arguments()
bam_fofn=args.bam_fofn
output_f = args.output_f
bed_f=args.bed_f
chrom_sizes_f=args.chrom_sizes_f
chrom = args.chrom




bam_files=pd.read_csv(bam_fofn,header=None)
bam_files=bam_files[0]

chrom_sizes=pd.read_csv(chrom_sizes_f,header=None,sep='\t',index_col=[0])
chrom_size=chrom_sizes.loc[chrom,1]


bed = pd.read_csv(bed_f,header=None,sep='\t')
bed=bed.loc[bed[0]==chrom,:]

########
#Checks#
########
print(chrom_size,flush=True)
assert  bed.shape[0] > 0, 'BED file {bed_f} is empty or has no break points for chromsome {chrom}'.format(bed_f=bed_f,chrom=chrom)
assert  math.log2(chunks) % np.floor(math.log2(chunks)) == 0, 'chunks must be an exponent of 2: 2,4,8,16,32,64,128...'


###########
#Splitting#
###########
iters=int(math.log2(chunks))
splits=split_chr(bed,bam_files,chrom,0,chrom_size-1,iters=iters)
split_intervals=merge_splits(splits)
print(split_intervals,flush=True)
print("Number of chunks: {chunks}".format(chunks=len(split_intervals)),flush=True)

##############
#Post-checks##
##############

#Checking if total reads within suggested intervals is the same as total reads
total_within=0
total_reads,_,_=compute_bam_counts(bam_files,0,chrom_size-1,[chrom,0,chrom_size-1])
for i,split_interval in enumerate(split_intervals):
    print(split_interval,flush=True)
    within,left,right=compute_bam_counts(bam_files,split_interval[0],split_interval[1],[chrom,split_interval[0],split_interval[1]] )
    total_within+=within
    print(within,flush=True)
    print('-----',flush=True)
    split_intervals[i].append(within)
print( 'Number of reads within region {total_within}. Number of reads in chromosome: {total_reads}'.format(total_within=total_within,total_reads=total_reads),flush=True )
assert total_within==total_reads, 'Total reads within regions is not equal to total number of reads for chromosome. BED file not output'

##############################
###If all is good: Output#####
##############################
output_bed=pd.DataFrame({0:[chrom for _ in split_intervals], 1: [split_interval[0] for split_interval in split_intervals], 2: [split_interval[1] for split_interval in split_intervals],3:  [split_interval[2] for split_interval in split_intervals]})
output_bed.to_csv(output_f,sep='\t',header=False,index=False)
