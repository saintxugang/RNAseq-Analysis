#!/bin/bash
#copy all ".genes.results" files to empty WD
# qsub -V -cwd -l h_vmem=4G -pe shm 12 -e KO2_v_AzL.err -o KO2_v_AzL.out ./RSEM-diff-express.2_condition.sh

#SET EXPERIMENT NAME HERE & change in .err names
name="KO2_v_AzL"

#########################################################################################
#‘rsem-generate-data-matrix’ extracts input matrix from expression results:
#Usage:
#rsem-generate-data-matrix sampleA.genes.results sampleB.genes.results ... > output_name.counts.matrix
echo rsem-generate-data-matrix
rsem-generate-data-matrix \
./H1_KO2/H1_KO2.genes.results \
./H1_AzL/H1_AzL.genes.results \
> $name.counts.matrix

#########################################################################################
#‘rsem-run-ebseq’ calls EBSeq to calculate related statistics for all genes/transcripts
#Usage:
#rsem-run-ebseq [options] data_matrix_file conditions output_file_name
echo rsem-run-ebseq
rsem-run-ebseq $name.counts.matrix 1,1 $name.DE.results

#data_matrix_file : m by n matrix. m = # of genes & n is # of total samples.
#Each element in the matrix represents the expected count for a particular
#gene/transcript in a particular sample.-> generate this file from expression result files.

#conditions
#Comma-separated list of values representing the number of replicates for each condition.
#For example, "3,3" means the data set contains 2 conditions and each condition has 3 replicates.
#"2,3,3" means the data set contains 3 conditions, with 2, 3, and 3 replicates for each condition respectively.

#########################################################################################
#‘rsem-control-fdr’ takes ‘rsem-run-ebseq’ result & reports called DE genes by controlling the FDR
#Usage:
#rsem-control-fdr [options] input_file fdr_rate output_file_name
echo rsem-control-fdr
rsem-control-fdr $name.DE.results 0.05 $name.DE_FDR05_1.txt

#input_file = This should be the main result file generated by 'rsem-run-ebseq',
#which contains all genes/transcripts and their associated statistics.

#fdr_rate = The desired false discovery rate (FDR).

#output_file = This file is a subset of the 'input_file'. It only contains the
#genes/transcripts called as DE. When > 2 conditions exist, DE is defined as not all
#conditions are equally expressed. Because statistical significance does not necessarily
#mean biological significance, users should also refer to the fold changes to decide which
#genes/transcripts are biologically significant.
#When more than two conditions exist, this file will not contain fold change information
#and users need to calculate it from 'input_file.condmeans' by themselves.

cat $name.DE_FDR05_1.txt | cut -f1,2,5 | tr -d '"' | tail -n+2 > $name.DE_FDR05.txt
rm $name.DE_FDR05_1.txt