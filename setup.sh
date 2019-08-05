#!/bin/bash

echo "
	############################################################################################################################
	############################## FACS pipeline - Fast AMP Clustering System               ####################################
	############################################################################################################################
	############################## Authors: Célio Dias Santos Júnior, Luis Pedro Coelho     ####################################
	############################################################################################################################
	############################## Institute > ISTBI - FUDAN University / Shanghai - China  ####################################
	############################################################################################################################"

read -p "[ Installing message ] :: Do you have already installed in your path conda? (1 - yes; 0 - no)
>>>>>> " conda_if

if [[ $conda_if == "1" ]]
then
	echo "[ ... Skipping initial procedures ]"
elif [[ -n $conda_if ]]
then
	echo "[ User ignored the question, sorry. Closing! ]"
else
	echo "[ Getting Bioconda -- It can take a while... ]"
	curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
	sh Miniconda3-latest-Linux-x86_64.sh
	conda config --add channels r	
	conda config --add channels defaults
	conda config --add channels bioconda
	conda config --add channels conda-forge
fi

echo "[ ## 1.] Installing routine linux softwares"
echo "# Creating environment of execution of routine softwares"
mkdir envs
conda create -p ./envs/FACS_env python=3.7
conda activate ./envs/FACS_env

echo "# Installing routine linux softwares"
conda install -c conda-forge sqlite
conda install -c conda-forge trimmomatic megahit pandaseq paladin samtools eXpress pigz parallel

echo "# Installing routine python packages"
conda install -c conda-forge matplotlib
conda install -c conda-forge scikit-learn
conda install -c conda-forge pandas
conda install -c conda-forge argparse

echo "# Installing routine R packages"
conda install -c conda-forge r-essentials r-base r-caret r-randomforest r-dplyr r-data.table

echo "# Closing environment"
conda deactivate

echo "[ ## 2.] Installing prodigal_modified_version"

echo "# Downloading from private repository"
wget --header 'Host: zenodo.org' --user-agent 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' --header 'Accept-Language: en-US,en;q=0.5' --referer 'https://zenodo.org/record/3360397' --header 'Cookie: session=96c7585046fec0b4_5d26b9d6.1K9hf9kCrXKIcVqZhq7L-o8rK5Q; __atuvc=5%7C28%2C1%7C29%2C0%7C30%2C0%7C31%2C5%7C32; __atssc=google%3B2; _pk_id.57.a333=88b4a4e2ffa2de44.1562733750.9.1565002224.1565000436.; _pk_ref.57.a333=%5B%22%22%2C%22%22%2C1565000436%2C%22https%3A%2F%2Fmail.google.com%2Fmail%2Fu%2F0%2F%22%5D; _pk_ses.57.a333=*; __atuvs=5d48055937bda6f9004; __atrfs=ab/|pos/|tot/|rsi/5d48059d00000000|cfc/|hash/0|rsiq/|fuid/fc115b49|rxi/|rsc/|gen/1|csi/|dr/' --header 'Upgrade-Insecure-Requests: 1' 'https://zenodo.org/record/3360397/files/prodigal?download=1' --output-document 'prodigal'
echo "# Unpacking"
chmod +x prodigal
mv prodigal envs/FACS_env/bin/

echo "[ ## 3.] Getting python scripts"
echo "# Downloading"
curl -O https://raw.githubusercontent.com/Superzchen/iLearn/master/descproteins/CTDDClass.py
curl -O https://raw.githubusercontent.com/Superzchen/iLearn/master/descproteins/readFasta.py 
curl -O https://raw.githubusercontent.com/Superzchen/iLearn/master/descproteins/saveCode.py
echo "# Modifying"
chmod +x *.py

echo "############ Installation procedures finished"