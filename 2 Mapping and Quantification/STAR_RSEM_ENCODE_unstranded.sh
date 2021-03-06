#!/bin/bash

##### STAR mapping / RSEM quantification pipeline #####

## run command:
## for x in `/bin/ls *.trim.R1.fq.gz` ; do bash STAR_RSEM_ENCODE_unstranded.sh $x; done

## set variable names
read1=`echo $1` #gzipped fastq file for read1
name=`basename $1 .trim.R1.fq.gz` #for trimmed
read2=$name.trim.R2.fq.gz #gzipped fq file for read2, use "" if single-end

## add required modules
module add STAR
module add samtools
module add rsem
module add r
module add ucsc_tools

# STAR genome directory, RSEM reference directory - prepared with STAR_RSEM_prep.sh script
STARgenomeDir="/home/jchap14/hi_quota_folder/Annotations/GENCODE-v19-GRCh37-hg19/STAR_genome_GRCh37_directory/"
RSEMrefDir="/home/jchap14/hi_quota_folder/Annotations/GENCODE-v19-GRCh37-hg19/RSEM_genome_GRCh37_directory/GRCh37"
nThreadsSTAR="12" # number of threads for STAR
nThreadsRSEM="12" # number of threads for RSEM

# executables
STAR=STAR                             
RSEM=rsem-calculate-expression        
bedGraphToBigWig=bedGraphToBigWig              

# STAR parameters: common
STARparCommon=" --genomeDir $STARgenomeDir  --readFilesIn ../$read1 ../$read2 --outFileNamePrefix $name. --outSAMunmapped Within --outFilterType BySJout \
 --outSAMattributes NH HI AS NM MD    --outFilterMultimapNmax 20   --outFilterMismatchNmax 999   \
 --outFilterMismatchNoverReadLmax 0.04   --alignIntronMin 20   --alignIntronMax 1000000   --alignMatesGapMax 1000000   \
 --alignSJoverhangMin 8   --alignSJDBoverhangMin 1 --sjdbScore 1 --readFilesCommand zcat"

# STAR parameters: run-time, controlled by DCC
STARparRun=" --runThreadN $nThreadsSTAR --genomeLoad LoadAndKeep  --limitBAMsortRAM 10000000000"

# STAR parameters: type of BAM output: quantification or sorted BAM or both
#     OPTION: sorted BAM output
## STARparBAM="--outSAMtype BAM SortedByCoordinate"
#     OPTION: transcritomic BAM for quantification
## STARparBAM="--outSAMtype None --quantMode TranscriptomeSAM"
#     OPTION: both
STARparBAM="--outSAMtype BAM SortedByCoordinate --quantMode TranscriptomeSAM"

# STAR parameters: strandedness, affects bedGraph (wiggle) files and XS tag in BAM 
STARparStrand="--outSAMstrandField intronMotif"
STARparWig="--outWigStrand Unstranded"

# RSEM parameters: common
RSEMparCommon="--bam --estimate-rspd --no-bam-output --seed 12345"

# RSEM parameters: run-time, number of threads and RAM in MB
RSEMparRun=" -p $nThreadsRSEM "

# RSEM parameters: data type dependent
RSEMparType="--paired-end"

## put the STAR & RSEM commands here ##
cat > $name.tempscript.sh << EOF
#!/bin/bash
#$ -j y
#$ -cwd
#$ -V
#$ -l h_vmem=4G
#$ -pe shm 12
#$ -l h_rt=5:59:00
#$ -l s_rt=5:59:00
#$ -N $name.STAR_RSEM

mkdir $name
cd $name

# output: all in the working directory, fixed names
# Aligned.sortedByCoord.out.bam                 # alignments, standard sorted BAM, agreed upon formatting
# Log.final.out                                 # mapping statistics to be used for QC, text, STAR formatting
# Quant.genes.results                           # RSEM gene quantifications, tab separated text, RSEM formatting
# Quant.isoforms.results                        # RSEM transcript quantifications, tab separated text, RSEM formatting
# Quant.pdf                                     # RSEM diagnostic plots
# Signal.{Unique,UniqueMultiple}.strand{+,-}.bw # 4 bigWig files for stranded data
# Signal.{Unique,UniqueMultiple}.unstranded.bw  # 2 bigWig files for unstranded data

###### STAR command
echo "STARTING STAR"
echo $STAR $STARparCommon $STARparRun $STARparBAM $STARparStrand
$STAR $STARparCommon $STARparRun $STARparBAM $STARparStrand

###### bedGraph generation, now decoupled from STAR alignment step
echo "STARTING STAR bedGraph generation"
mkdir Signal

echo $STAR --runMode inputAlignmentsFromBAM --inputBAMfile $name.Aligned.sortedByCoord.out.bam --outWigType bedGraph $STARparWig --outFileNamePrefix ./Signal/ --outWigReferencesPrefix chr
$STAR --runMode inputAlignmentsFromBAM --inputBAMfile $name.Aligned.sortedByCoord.out.bam --outWigType bedGraph $STARparWig --outFileNamePrefix ./Signal/ --outWigReferencesPrefix chr

## move the signal files from the subdirectory
echo "move the signal files from the subdirectory"
mv Signal/Signal*bg .


###### bigWig conversion commands
echo "Start bigWig conversion"
grep ^chr $STARgenomeDir/chrNameLength.txt > chrNL.txt

for imult in Unique UniqueMultiple
do
grep ^chr Signal.\$imult.str1.out.bg > sig.tmp
bedSort sig.tmp sig.tmp
$bedGraphToBigWig sig.tmp chrNL.txt  Signal.\$imult.unstranded.bw
done
rm sig.tmp

##########################################################################################
######### RSEM
echo "Prepare for RSEM: sorting BAMs"

#### prepare for RSEM: sort transcriptome BAM to ensure the order of the reads, to make RSEM output (not pme) deterministic
mv $name.Aligned.toTranscriptome.out.bam Tr.bam 

# paired-end data, merge mates into one line before sorting, and un-merge after sorting
echo "cat <( samtools view -H Tr.bam ) <( samtools view -@ $nThreadsRSEM Tr.bam | awk '{printf \"%s\", \$0 \" \"; getline; print}' | sort -S 60G -T ./ | tr ' ' '\n' ) | samtools view -@ $nThreadsRSEM -bS - > $name.Aligned.toTranscriptome.out.bam"
cat <( samtools view -H Tr.bam ) <( samtools view -@ $nThreadsRSEM Tr.bam | awk '{printf "%s", \$0 " "; getline; print}' | sort -S 60G -T ./ | tr ' ' '\n' ) | samtools view -@ $nThreadsRSEM -bS - > $name.Aligned.toTranscriptome.out.bam
'rm' Tr.bam

###### RSEM command
echo "STARTING RSEM"
echo $RSEM $RSEMparCommon $RSEMparRun $RSEMparType $name.Aligned.toTranscriptome.out.bam $RSEMrefDir $name >& $name.Log.rsem
$RSEM $RSEMparCommon $RSEMparRun $RSEMparType $name.Aligned.toTranscriptome.out.bam $RSEMrefDir $name >& $name.Log.rsem

###### RSEM diagnostic plot creation
# Notes:
# 1. rsem-plot-model requires R (and the Rscript executable)
# 2. This command produces the file $name.pdf, which contains multiple plots
echo "STARTING RSEM-plot-model"
echo rsem-plot-model $name $name.pdf
rsem-plot-model $name $name.pdf

EOF
# qsub then remove the tempscript
qsub $name.tempscript.sh 
sleep 1
rm $name.tempscript.sh
