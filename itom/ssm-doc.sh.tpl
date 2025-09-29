 #!/bin/bash
          echo "Starting SSM document execution..."

          function getClusters() {
            echo "Fetching EKS clusters from us-west-2..."
            names=$(aws eks list-clusters --region us-west-2 | tail -n +3 | head -n -2 | tr -s ' ' | cut -d ' ' -f 2 | cut -d '"' -f 2)
            IFS=$' ' read -d '' -r -a clusters <<< $names
          }
          function getContexts() {
            names=$(kubectl config get-contexts --no-headers| tr -s ' ' | cut -d ' ' -f 2 )
            IFS=$' ' read -d '' -r -a k8names <<< $names
          }
          getClusters
          for ((n=0; n<$${#clusters[@]}; n++)); do
            echo "  $${clusters[$n]} " | sed 's/^/#EKS-NAME#/'
            aws eks update-kubeconfig --name $${clusters[$n]} --region us-west-2
          done
          export KUBECONFIG=/root/.kube/config
          getContexts
          for ((n=0; n<$${#k8names[@]}; n++)); do
            echo "  $${k8names[n]} " | sed 's/^/#EKS-ARN#/'
          done
          echo "Done."
          kubectl config view
          echo "SSM document execution completed successfully."
