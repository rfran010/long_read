#!/bin/bash -l

#SBATCH -p batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=64G       #Units available, K, M, G, T
#SBATCH --time=2-00:00:00       #d-hh:mm:ss
#SBATCH --mail-user=rfran010@ucr.edu
#SBATCH --mail-type=ALL
#SBATCH --job-name=fast5_to_pod5
#SBATCH --output=%x_%j.out

module load pod5/0.3.23

set -e

input_dir=${1}

index='GRCm38.primary_assembly.genome.fa'
chrom_sizes='GRCm38.primary_assembly.genome.fa.chromSizes'
binary_bg2bw='UCSC_tools/bedGraphToBigWig'
binary_bedSort='UCSC_tools/bedSort'
mods="6mA"
model="hac"

pod5 convert fast5 ${input_dir}/*fast5 --output output_pod5/ --one-to-one ${input_dir}

wait

mv ${input_dir} ${input_dir}_pod5
