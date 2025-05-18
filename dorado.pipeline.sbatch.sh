#!/bin/bash -l

#SBATCH -p gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:a100:4
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G       #Units available, K, M, G, T
#SBATCH --time=2-00:00:00       #d-hh:mm:ss
#SBATCH --mail-user=rfran010@ucr.edu
#SBATCH --mail-type=ALL
#SBATCH --job-name=dorado_pipe
#SBATCH --output=%x_%j.out

# Reuben Franklin, rfran010@ucr.edu
# Pipeline is designed for SLURM HPC to process the latest (20250501) ONT long read pod5 data. If data is in fast5, conversion is needed.
# Script takes a title as the first argument and a directory of pod5 files as the second argument.
# see dependencies below.
# $ sbatch dorado.pipeline.sbatch.sh ExampleTitle dorado_pod5_files/

# Dorado can be installed via conda. We have it installed as module.
# conda activate dorado
module load dorado/0.8.2

set -e

# DEPENDENCIES: modkit, UCSC binaries: bedGraphToBigWig, bedSort
# change variables to point to correct location of relevant binaries.
# also provide genome fasta you want to align to as "index"
modkit_binary='modkit_v0.4.4/modkit'
index='GRCm38.primary_assembly.genome.fa'
chrom_sizes='GRCm38.primary_assembly.genome.fa.chromSizes'
binary_bg2bw='UCSC_tools/bedGraphToBigWig'
binary_bedSort='UCSC_tools/bedSort'

# what mods do you want to call, and how accurate/fast (see Dorado github page for available options/combinations).
# Also depends on data version.
mods="6mA"
model="hac"

# Takes two command line arguments
title=${1}
data_dir=${2}
bam_calls=${title}_calls.bam
bam_align=${title}_align.bam
bam_sort=${title}_sort.align.bam
bg_temp1=${title}_temp_bedgraph1.tmp
bg_temp2=${title}_temp_bedgraph2.tmp

basecalls_summary=${title}_summary.tsv

dorado basecaller \
  --modified-bases ${mods} \
  --verbose \
  ${model} \
  ${data_dir} \
  > ${bam_calls}

sbatch \
  -p short \
  --mem=16G \
  --cpus-per-task=4 \
  --job-name=dorado_02_summary \
  --output=\%x_\%j.out \
  --wrap="dorado summary ${bam_calls} > ${basecalls_summary}"

align_id=$( \
  sbatch \
    -p batch \
    --mem=64G \
    --cpus-per-task=36 \
    --job-name=dorado_03_align \
    --time=2-00:00:00 \
    --output=\%x_\%j.out \
    --parsable \
    --wrap="dorado aligner --threads \${SLURM_CPUS_PER_TASK} ${index} ${bam_calls} > ${bam_align}" \
)

sort_id=$(
  sbatch \
    --dependency=afterok:${align_id} \
    -p batch \
    --mem=36G \
    --time=0-12:00:00 \
    --cpus-per-task=4 \
    --job-name=dorado_04_sort-index \
    --output=\%x_\%j.out \
    --parsable \
    --wrap="module load samtools; samtools sort --threads \$(( \${SLURM_CPUS_PER_TASK} - 1 )) ${bam_align} > ${bam_sort}; samtools index ${bam_sort}" \
)

bedgraph_id=$(
  sbatch \
    --dependency=afterok:${sort_id} \
    -p batch \
    --mem=64G \
    --time=0-12:00:00 \
    --cpus-per-task=16 \
    --job-name=dorado_05_bedgraph \
    --output=\%x_\%j.out \
    --parsable \
    --wrap="${modkit_binary} pileup --threads \${SLURM_CPUS_PER_TASK} ${bam_sort} ./ --bedgraph --prefix ${title}" \
)


sbatch \
  --dependency=afterok:${bedgraph_id} \
  -p batch \
  --mem=48G \
  --time=0-12:00:00 \
  --cpus-per-task=4 \
  --job-name=dorado_06_bg2bw \
  --output=\%x_\%j.out \
  --wrap="for bedgraph in ${title}_?_*.bedgraph; do cut -f1-4 \${bedgraph} > ${bg_temp1};  /rhome/rfran010/scripts/UCSC_tools/bedSort ${bg_temp1} ${bg_temp1}.srt.tmp; ${binary_bg2bw} ${bg_temp1}.srt.tmp ${chrom_sizes} \${bedgraph/.bedgraph/}.bw; done; rm ${bg_temp1} ${bg_temp1}.srt.tmp"

sbatch \
  --dependency=afterok:${bedgraph_id} \
  -p batch \
  --mem=48G \
  --time=0-12:00:00 \
  --cpus-per-task=4 \
  --job-name=dorado_07_bg2bw \
  --output=\%x_\%j.out \
  --wrap="for bedgraph in ${title}_?_*.bedgraph; do cut -f1-3,5 \${bedgraph} > ${bg_temp2};  /rhome/rfran010/scripts/UCSC_tools/bedSort ${bg_temp2} ${bg_temp2}.srt.tmp; ${binary_bg2bw} ${bg_temp2}.srt.tmp ${chrom_sizes} \${bedgraph/.bedgraph/.coverage.bw}; done; rm ${bg_temp2} ${bg_temp2}.srt.tmp"

sbatch \
  --dependency=afterok:${bedgraph_id} \
  -p batch \
  --mem=48G \
  --time=0-12:00:00 \
  --job-name=dorado_08_pileup \
  --output=\%x_\%j.out \
  --wrap="${modkit_binary} pileup ${bam_sort} ${title}_pileup.bed --log-filepath ${title}_pileup.log"
