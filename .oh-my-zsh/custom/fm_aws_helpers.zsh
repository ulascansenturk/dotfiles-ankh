# Forwards any address:port in the staging VPC to your local machine through an SSH tunnel
# Usage: forward_staging LOCAL_PORT:ADDRESS:REMOTE_PORT
# Example: forward_staging 12000:database-writer.staging-bank-account:3306
forward_staging() {
  PROFILE='root'

  # Must have the format LOCAL_PORT:ADDRESS:REMOTE_PORT
  TUNNEL=$1

  get_credentials $PROFILE

  JQ_QUERY=".Reservations[] | select(.Instances | first | .Tags | .[] | .Value | contains(\"staging-bastion\")) | .Instances | first | .InstanceId"
  HOST_ID=$(aws ec2 describe-instances --profile $PROFILE --region eu-west-1 | jq $JQ_QUERY | tr -d '"')

  [[ -z "$HOST_ID" ]] && echo "Host not found" && return
  mssh -L $TUNNEL $HOST_ID -N -v --profile $PROFILE --region eu-west-1
}

# refresh_session production-backend|staging-backend|root
#   will open a browser page to refresh your SSO session
refresh_session() {
  aws sts get-caller-identity --profile $1 > /dev/null
  if [[ $? != 0 ]]; then
    aws sso login --profile "$1"
  fi
}

get_credentials() {
  PROFILE="$1"
  refresh_session $PROFILE

  ACCOUNT_ID=$(aws configure get sso_account_id --profile $PROFILE)
  ROLE_NAME=$(aws configure get sso_role_name --profile $PROFILE)

  #Retrieve cached accessToken
  JQ_QUERY='.accessToken'
  ACCESS_TOKEN=$(ls ~/.aws/sso/cache | grep -m1 -v botocore | xargs -I{} cat ~/.aws/sso/cache/{} | jq -r $JQ_QUERY)

  # Retrieve credentials
  CREDENTIALS=$(aws sso get-role-credentials --role-name $ROLE_NAME --account-id $ACCOUNT_ID --access-token $ACCESS_TOKEN --output json --region eu-west-1)
  if [[ $CREDENTIALS == "" ]]; then
    echo "Could not retrieve credentials, please log in the SSO portal" 1>&2;
  fi

  AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.roleCredentials.accessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.roleCredentials.secretAccessKey')
  AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.roleCredentials.sessionToken')

  # Write credentials
  if grep "\[$PROFILE\]" ~/.aws/credentials > /dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/\[$PROFILE\]/,/\[/{s/aws_access_key_id.*/aws_access_key_id = ${AWS_ACCESS_KEY_ID//\//\\/}/;}" ~/.aws/credentials
      sed -i '' "/\[$PROFILE\]/,/\[/{s/aws_secret_access_key.*/aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY//\//\\/}/;}" ~/.aws/credentials
      sed -i '' "/\[$PROFILE\]/,/\[/{s/aws_session_token.*/aws_session_token = ${AWS_SESSION_TOKEN//\//\\/}/;}" ~/.aws/credentials
    else
      sed -i "/\[$PROFILE\]/,/\[/{s/aws_access_key_id.*/aws_access_key_id = ${AWS_ACCESS_KEY_ID//\//\\/}/;}" ~/.aws/credentials
      sed -i "/\[$PROFILE\]/,/\[/{s/aws_secret_access_key.*/aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY//\//\\/}/;}" ~/.aws/credentials
      sed -i "/\[$PROFILE\]/,/\[/{s/aws_session_token.*/aws_session_token = ${AWS_SESSION_TOKEN//\//\\/}/;}" ~/.aws/credentials
    fi
  else
    echo "[$PROFILE]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
" >> ~/.aws/credentials
  fi
}

# Connect to an instance in a Elastic Beanstalk environment
# eb_ssh --environment staging-scoring-algo --key staging_data_science_api --profile staging-data-science-api
eb_ssh() {
  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        echo "eb_ssh - connect in SSH to an Elastic Beanstalk instance via SSM"
        echo " "
        echo "eb_ssh [options]"
        echo " "
        echo "options:"
        echo "-h, --help           show brief help"
        echo "-e, --environment    specify the Elastic Beanstalk environment name"
        echo "-k, --key            specify the SSH key name (will look for it in ~/.ssh/$key.pem)"
        echo "-p, --profile        specify the AWS profile"
        exit 0
        ;;
      -e|--environment)
        shift
        if test $# -gt 0; then
          ENVIRONMENT=$1
        else
          echo "No environment specified"
          exit 1
        fi
        shift
        ;;
      -k|--key)
        shift
        if test $# -gt 0; then
          SSH_KEY=$1
        else
          echo "No SSH key specified"
          exit 1
        fi
        shift
        ;;
      -p|--profile)
        shift
        if test $# -gt 0; then
          PROFILE=$1
        else
          echo "No profile specified"
          exit 1
        fi
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY.pem"
  PROXY_COMMAND="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --profile $PROFILE --region eu-west-1"
  HOST_ID=$(aws elasticbeanstalk describe-environment-resources --environment-name $ENVIRONMENT --output json --profile $PROFILE --region eu-west-1 --query "EnvironmentResources.Instances[0].Id")
  # remove possible double quotes
  HOST_ID=${HOST_ID%\"}
  HOST_ID=${HOST_ID#\"}
  ssh -o ProxyCommand="$PROXY_COMMAND" -i $SSH_KEY_PATH $HOST_ID -l ec2-user
}

forward_vpc_endpoint() {
  BASTION=production
  AWS_PROFILE=root
  VERBOSE=

  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        echo ""
        echo "forward_vpc_endpoint - Forward a VPC endpoint and remap it to a local port"
        echo ""
        echo "forward_vpc_endpoint [options]"
        echo ""
        echo "options:"
        echo "-h, --help           show brief help"
        echo "-e, --endpoint       specify the endpoint within the VPC"
        echo "-p, --endpoint-port  specify the endpoint port"
        echo "-l, --local-port     specify the local port"
        echo "-b, --bastion        specify the instance bastion to use (staging or production) - default to production"
        echo "-v, --verbose        turn on verbose mode"
        echo "--profile            specify the AWS profile - default to root"
        echo ""
        echo "examples:"
        echo "forward_vpc_endpoint --endpoint database-reader.production.com --endpoint-port 3306 --local-port 9000 --bastion production --verbose"
        echo "forward_vpc_endpoint --endpoint api.staging-bank-account       --endpoint-port 443  --local-port 3000 --bastion staging    --verbose"
        echo ""
        exit 0
        ;;
      -e|--endpoint)
        shift
        if test $# -gt 0; then
          DATABASE_ENDPOINT=$1
        else
          echo "No database endpoint specified"
          exit 1
        fi
        shift
        ;;
      -p|--endpoint-port)
        shift
        if test $# -gt 0; then
          ENDPOINT_PORT=$1
        else
          echo "No endpoint port specified"
          exit 1
        fi
        shift
        ;;
      -l|--local-port)
        shift
        if test $# -gt 0; then
          LOCAL_PORT=$1
        else
          echo "No local port specified"
          exit 1
        fi
        shift
        ;;
      -b|--bastion)
        shift
        if test $# -gt 0; then
          BASTION=$1
        fi
        shift
        ;;
      -v|--verbose)
        VERBOSE="-v"
        shift
        ;;
      --profile)
        shift
        if test $# -gt 0; then
          AWS_PROFILE=$1
        fi
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  echo "Forwarding VPC endpoint..."
  BASTION_INSTANCE_ID=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --filters Name=tag-value,Values=$BASTION-bastion Name=instance-state-name,Values=running --region eu-west-1 --profile $AWS_PROFILE --output text)
  mssh -L $LOCAL_PORT:$DATABASE_ENDPOINT:$ENDPOINT_PORT $BASTION_INSTANCE_ID -N $VERBOSE --region eu-west-1 --profile $AWS_PROFILE -o IdentitiesOnly=yes vps2
}
