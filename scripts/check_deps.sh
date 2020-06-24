!#/bin/bash

$CI_PROJECT_DIR/Supply/ST_$COMMIT
DEP=`cat {{ work_dir }}/Supply/ST_{{ commit }}/CR_dependencies.txt | grep -v "#"`

for line in $DEP
do
sshpass -p "{{ somebase.passw }}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "{{ somebase.user }}"@"{{ host }}" "/tmp/distribs/aixcheck.sh  $line"
done