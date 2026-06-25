import os
import argparse
import scanpy as sc
import anndata as ad
import pandas as pd

def read_mtx(directory):
    adata = sc.read_10x_mtx(directory)
    return adata

def is_empty_mtx(directory):
    """Return True if the 10x MTX directory has no features (e.g. chrM with 0 reads)."""
    for fname in ('features.tsv', 'features.tsv.gz', 'genes.tsv', 'genes.tsv.gz'):
        fpath = os.path.join(directory, fname)
        if os.path.exists(fpath):
            return os.path.getsize(fpath) == 0
    # No features/genes file at all -> treat as empty
    return True

def merge_mtx(directories):
    adatas = []
    for directory in directories:
        if is_empty_mtx(directory):
            print('Skipping empty MTX dir {d}...'.format(d=directory),flush=True)
            continue
        adatas.append(read_mtx(directory))
        print('Read {d}...'.format(d=directory),flush=True)
    if len(adatas) == 0:
        print('WARNING: all input MTX directories are empty; writing an empty AnnData.',flush=True)
        return ad.AnnData()
    merged_adata = ad.concat(adatas, join='outer',axis=1)
    return merged_adata

def save_to_hdf5(adata, output_file):
    adata.write_h5ad(output_file)

def main():
    parser = argparse.ArgumentParser(description="Merge multiple MTX files into a single HDF5 file using Scanpy and AnnData.")
    parser.add_argument("-i", "--input_dirs", nargs="+", required=True, help="List of directories containing MTX files.")
    parser.add_argument("-d", "--output_dir", required=False,default=None, help="Output directory for the HDF5 file.")
    parser.add_argument("-p", "--prefix", required=False, default=None,help="Prefix for the output HDF5 file.")

    args = parser.parse_args()

    input_dirs=args.input_dirs
    if args.prefix is None:
        prefix='OUT'
    else:
        prefix=args.prefix
    if args.output_dir is not None:
        os.makedirs(args.output_dir, exist_ok=True)
        output_dir=args.output_dir
    else:
        output_dir='./'


    output_file = os.path.join(output_dir, f"{prefix}.h5ad")

    print('Processing: {n} MTX files:'.format(n=len(input_dirs)))
    print(', '.join(input_dirs))
    adata = merge_mtx(input_dirs)
    save_to_hdf5(adata, output_file)

    print(f"Merged HDF5 file saved to {output_file}")

if __name__ == "__main__":
    main()
