 #!/bin/bash

export ANSIBLE_HOST_KEY_CHECKING=false

source ./scripts/common_func.sh

if check_branch; then
    echoout "I;" "start; COMMIT=$COMMIT P_DEPLOY=$P_DEPLOY BRANCH=$BRANCH "
    if [[ "$P_DEPLOY" == "true" ]]; then
        echo "Start deploy, artifacts in `pwd`:"
        ls -l *.zip *.txt *.docx *.tar.gz || true
        ansible-playbook --extra-vars "commit=$COMMIT workdir=$CI_PROJECT_DIR host=$BRANCH" -i inventories/hosts yml/somebasedeploy.yml --diff -b -vv
      else
        echo "deploy-disabled-P_DEPLOY-$P_DEPLOY" > deploy_result-$COMMIT.txt   
      fi        
else
    echoout "I;" "Deploy from branch or tag = COMMIT ($COMMIT), skip deploy"
fi

