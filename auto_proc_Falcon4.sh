#!/bin/bash

# Prompt user for input
read -p "Enter the base directory for image processing (ends in "/", e.g. /data1/Shujun/krios/rec/20250120/): " BASE_DIR
read -p "Enter the directory containing raw data in /data1/share/krios/ (ends in "/", e.g. /data1/share/krios/20250120/20250120slot3/): " SOURCE_DIR
read -p "Enter the number of raw frames per EER (e.g. 252): " RAW_FRAMES
read -p "Enter the number of raw frames to be grouped into one (e.g. 36): " GROUP_FRAMES
read -p "Enter the dose (e-/A2) per raw frame (e.g. 0.09): " DOSE_PER_FRAME

# Ensure the input ends with a slash
BASE_DIR="${BASE_DIR%/}/"
SOURCE_DIR="${SOURCE_DIR%/}/"

# Create folders including Motioncorr Gctf st
cd "${BASE_DIR}"
mkdir Motioncorr Gctf st


# Run commands with the user-provided directory

# Create falcon_06.txt file for motion correction

# Define the output file name
Falcon06_FILE="falcon06.txt"

# Write the inputs to a single line in the file
echo "$RAW_FRAMES $GROUP_FRAMES $DOSE_PER_FRAME" > "$Falcon06_FILE"


# Motion correction

module load MotionCor2

for f in ${SOURCE_DIR}*.eer; do
prfx="$(basename ${f} .eer)"
echo; echo "${prfx}.eer"

MotionCor2 -InEer "${SOURCE_DIR}${prfx}.eer" -OutMrc ${BASE_DIR}Motioncorr/${prfx}_motioncorr.mrc -FmIntFile ${BASE_DIR}Motioncorr/falcon06.txt -EerSampling 1 -FmDose 1 -PixSize 2.109 -kV 300 -Gain ${SOURCE_DIR}*.gain -Patch 4,4 -Tol 0.5 -Bft 100 -Cs 0.01 -Gpu 0,1,2,3

done

module purge

# CTF correction
cd "${BASE_DIR}Motioncorr"
rm -f *DW.mrc #delete dose weighted mrc
module load Gctf
GCTF --apix 2.109 --kV 300 --cs 0.01 --ac 0.1 --do_phase_flip 1 ./*corr.mrc
module purge
mv *pf.mrc "${BASE_DIR}Gctf/"
cd "${BASE_DIR}Gctf"

# Combine tilt series
module load imod

# Define the Python script filename
PYTHON_SCRIPT="combineTiltseries.py"

# Create the Python script using a here-document
cat << EOF > "$PYTHON_SCRIPT"

# Python script

import os
from collections import defaultdict

def main():

    #current directory of the tilts
    path = os.getcwd()
    #print path

    #create a dictionary based on the tilt series number
    #key is the tilt series number
    #values are the filenames of tilts
    groups = defaultdict(list)
    for filename in os.listdir(path):
        if filename.endswith(".mrc"):
            basename, extension = os.path.splitext(filename)
            #print basename
            tiltSeriesNum, tiltAngle = basename.split('_')[2], basename.split('_')[4]
            groups[tiltSeriesNum].append(filename)

    #key is the tilt series number
    #values are the filenames of tilts
    #sort in each list of values by the tilt angles (the third element in the filename, e.g. 'lamella_36_012_-0.0_Sep26_21.49.01_12_0.mrc')
    for key, values in groups.items():
        values.sort(key = lambda x: float(x.split('_')[4]))
        print key, values
        print "\n"
        rootName, tiltSeriesNum = values[0].split('_')[1:3]
        tiltSeriesName = rootName + '_' + tiltSeriesNum + '.st'
        rawTiltName = rootName + '_' + tiltSeriesNum + '.rawtlt'
        print tiltSeriesName

        fp = open(rawTiltName, 'w')

        #combine individual tilt into a tilt series using imod command "newstack"
        cmd = 'newstack '
        for tiltName in values:
            tiltAngle = tiltName.split('_')[4]
            print tiltName, tiltAngle

            fp.write(str(tiltAngle) + '\n')
            cmd += tiltName + ' '
        cmd += tiltSeriesName
        fp.close()

        #run command
        os.system(cmd)
        print cmd

if __name__ == '__main__':

    # Calling main() function
    main()
EOF

python2 combineTiltseries.py

# Alter header in st files
for f in *.st; do
prfx="$(basename ${f} .st)"
echo; echo "${prfx}.st"
alterheader -del 2.109,2.109,2.109 -title "Tilt axis angle = -105" ${prfx}.st ${prfx}.st
done
mv *.st "${BASE_DIR}st"
mv *.rawtlt "${BASE_DIR}st"

echo "---------------------------------------------------------"
echo "All steps completed successfully! Check your output in:"
echo "${BASE_DIR}st"
echo "---------------------------------------------------------"
