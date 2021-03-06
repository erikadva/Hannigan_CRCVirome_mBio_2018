#! /bin/bash
# IdentifyContigs.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

export fastafile=$1
export referencefile=$2
export idfile=$3
export outputfile=$4
export BlastPath=$5
export runblastn=$6

# Get the contig representative sequences
mkdir -p ./data/tmpid

RunBlast () {
	# 1 = Query Seqs
	# 2 = ReferenceSeqs

	echo Making blast database...
	${BlastPath}makeblastdb \
		-dbtype nucl \
		-in "${2}" \
		-out ./data/tmpid/ReferenceGenomes

	# Use a higher max target seqs for filtering below
	echo Running tblastx...
	${BlastPath}tblastx \
    	-query "${1}" \
    	-out ./data/tmpid/blastout.tsv \
    	-db ./data/tmpid/ReferenceGenomes \
    	-evalue 1e-25 \
    	-num_threads 8 \
    	-max_target_seqs 100 \
    	-outfmt 6
}

RunBlastn () {
	# 1 = Query Seqs
	# 2 = ReferenceSeqs

	echo Making blast database...
	${BlastPath}makeblastdb \
		-dbtype nucl \
		-in "${2}" \
		-out ./data/tmpid/ReferenceGenomes

	echo Running blastn...
	${BlastPath}blastn \
    	-query "${1}" \
    	-out ./data/tmpid/blastout.tsv \
    	-db ./data/tmpid/ReferenceGenomes \
    	-evalue 1e-25 \
    	-num_threads 8 \
    	-max_target_seqs 1 \
    	-outfmt 6
}

export -f RunBlast
export -f RunBlastn

cut -f 1 ${idfile} | tail -n +2 > ./data/tmpid/contiglist.tsv
grep -A 1 -f ./data/tmpid/contiglist.tsv ${fastafile} \
	| egrep -v "\-\-" \
	> ./data/tmpid/contigrepset.fa

if [ $runblastn = true ]; then
	RunBlastn ./data/tmpid/contigrepset.fa ${referencefile}
else
	RunBlast ./data/tmpid/contigrepset.fa ${referencefile}
fi

# Add cluster ID to the table
sort -k2,2 -k11,11g -k 12,12Vr ./data/tmpid/blastout.tsv \
	| awk '!seen[substr($1,0,35)]++' \
	| cut -f 1,2 \
	> ./data/tmpid/cutblastout.tsv
sed 's/\,/\t/' ./data/ContigClustersVirus/clustering_gt1000.csv > ./data/tmpid/clusterids.tsv
awk -F "\t" 'FNR==NR { a[$1] = $2; next } { for( i in a ) if($1 ~ i) {print a[$1]"\t"$2} }' \
	./data/tmpid/clusterids.tsv \
	./data/tmpid/cutblastout.tsv \
	| sed 's/ENA|\(.\+\)|.*/\1/' \
	> ./data/tmpid/clustform.tsv

# Make list of IDs
cut -f 2 ./data/tmpid/clustform.tsv > ./data/tmpid/tmplist.tsv

grep --file=./data/tmpid/tmplist.tsv ./tmp-database-download/nucl_gb.accession2taxid > ./data/tmpid/taxlist.tsv

# Get the taxon IDs
awk -F "\t" 'FNR==NR { a[$1] = $3; next } { for( i in a ) if($2 ~ i) {print $1"\t"$2"\t"a[$2]} }' \
	./data/tmpid/taxlist.tsv  \
	./data/tmpid/clustform.tsv \
	> ./data/tmpid/ctax.tsv
cut -f 3 ./data/tmpid/ctax.tsv > ./data/tmpid/tmplist.tsv
# Download the information using the EBI API
while read line; do
	wget -O - "http://www.ebi.ac.uk/ena/data/taxonomy/v1/taxon/tax-id/${line}" \
	| grep "lineage" \
	| sed 's/.\+\: \"//' \
	| sed 's/\; \".*//' \
	| sed 's/\; /\t/g' \
	| sed 's/ /_/g' \
	| sed "s/^/${line}\t/"
done < ./data/tmpid/tmplist.tsv > ./data/tmpid/taxawnum.tsv

rm -rf ./data/tmpcter
mkdir -p ./data/tmpcter
for i in $(seq 1 8); do
	awk -v col=$i '{ if($col) print $col; else print "Unclassified" }' ./data/tmpid/taxawnum.tsv > ./data/tmpcter/${i}.tsv
done
paste ./data/tmpcter/* > ./data/tmpid/fullcols.tsv
sort ./data/tmpid/fullcols.tsv | uniq > ./data/tmpid/fullcols_filtered.tsv

# Get together the taxonomy reference and the contig IDs
awk -F "\t" 'FNR==NR { a[$1] = $0; next } { {print $1"\t"$2"\t"a[$3]} }' \
	./data/tmpid/fullcols_filtered.tsv \
	./data/tmpid/ctax.tsv \
	| cut -f -2,4- \
	> ./data/contigclustersidentity/clustax.tsv


