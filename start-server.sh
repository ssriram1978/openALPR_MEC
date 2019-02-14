#!/bin/bash 


OLD_FILE="old_image_lst.txt"
NEW_FILE="new_image_lst.txt" 

ls *.* > ${OLD_FILE} 

COUNT=0
while true ; do 
     echo ${COUNT}
     COUNT=$[ ${COUNT} + 1 ]
     ls *.* > ${NEW_FILE} 
     DIFF=($(comm -1 -3 ${OLD_FILE} ${NEW_FILE})) 
     if [ ${#DIFF[@]} -eq 0 ]; then 
         echo "no plate file uploaded..."
     else
         for f in "${DIFF[@]}" ; do
             echo "detect plate number in file: ${f}"
             alpr -c us ${f}  
         done   
     fi  
     sleep 10 
     mv ${NEW_FILE} ${OLD_FILE}
done


rm -f ${NEW_FILE} ${OLD_FILE} 


