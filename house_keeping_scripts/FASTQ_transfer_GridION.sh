run_folder=${1}
cd $HOME

YEAR=$(date +"%Y")

sudo cp -r ../../data/${run_folder} ../../mnt/N/NGS/3-Sekvenseringsbiblioteker/${YEAR}/Nanopore_Grid_Run/

echo "transfer done"
