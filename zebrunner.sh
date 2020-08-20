#!/bin/bash

  print_banner() {
  echo "
███████╗███████╗██████╗ ██████╗ ██╗   ██╗███╗   ██╗███╗   ██╗███████╗██████╗      ██████╗███████╗
╚══███╔╝██╔════╝██╔══██╗██╔══██╗██║   ██║████╗  ██║████╗  ██║██╔════╝██╔══██╗    ██╔════╝██╔════╝
  ███╔╝ █████╗  ██████╔╝██████╔╝██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝    ██║     █████╗  
 ███╔╝  ██╔══╝  ██╔══██╗██╔══██╗██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗    ██║     ██╔══╝  
███████╗███████╗██████╔╝██║  ██║╚██████╔╝██║ ╚████║██║ ╚████║███████╗██║  ██║    ╚██████╗███████╗
╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝     ╚═════╝╚══════╝
"

  }

  setup() {
    print_banner

    # load default interactive installer settings
    source backup/settings.env.original

    # load ./backup/settings.env if exist to declare ZBR* vars from previous run!
    if [[ -f backup/settings.env ]]; then
      source backup/settings.env
    fi

    export ZBR_INSTALLER=1
    set_global_settings

    cp nginx/conf.d/default.conf.original nginx/conf.d/default.conf

    export ZBR_INFRA_HOST=$ZBR_HOSTNAME

    sed -i 's/server_name localhost/server_name '$ZBR_HOSTNAME'/g' ./nginx/conf.d/default.conf
    sed -i 's/listen 80/listen '$ZBR_PORT'/g' ./nginx/conf.d/default.conf

    enableLayer "sonarqube" "SonarQube" "$ZBR_SONARQUBE_ENABLED"
    export ZBR_SONARQUBE_ENABLED=$?

    enableLayer "jenkins" "Jenkins" "$ZBR_JENKINS_ENABLED"
    export ZBR_JENKINS_ENABLED=$?

    enableLayer "mcloud" "Mobile Selenium Hub (Android, iOS, AppleTV etc)" "$ZBR_MCLOUD_ENABLED"
    export ZBR_MCLOUD_ENABLED=$?

    enableLayer "selenoid" "Web Selenium Hub (chrome, firefox and opera)" "$ZBR_SELENOID_ENABLED"
    export ZBR_SELENOID_ENABLED=$?

    enableLayer "reporting" "Zebrunner Reporting" "$ZBR_REPORTING_ENABLED"
    export ZBR_REPORTING_ENABLED=$?
    if [[ $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      set_reporting_settings

      enableLayer "reporting/minio-storage" "Minio S3 Storage for Reporting" "$ZBR_MINIO_ENABLED"
      export ZBR_MINIO_ENABLED=$?
      if [[ $ZBR_MINIO_ENABLED -eq 1 ]]; then
        set_minio_storage_settings
      else
        set_aws_storage_settings
      fi
      reporting/zebrunner.sh setup
    else
      # no need to ask about enabling minio sub-module
      disableLayer "reporting/minio-storage"
    fi

    if [[ $ZBR_SONARQUBE_ENABLED -eq 1 ]]; then
      sonarqube/zebrunner.sh setup
      export ZBR_SONAR_URL=$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/sonarqube
    fi

    if [[ $ZBR_JENKINS_ENABLED -eq 1 ]]; then
      jenkins/zebrunner.sh setup

      # update reporting-jenkins integration script
      cp reporting/database/reporting/sql/db-jenkins-integration.sql.original reporting/database/reporting/sql/db-jenkins-integration.sql
      sed -i "s#URL_VALUE#$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/jenkins#g" reporting/database/reporting/sql/db-jenkins-integration.sql
      sed -i "s#USER_VALUE#admin#g" reporting/database/reporting/sql/db-jenkins-integration.sql
      sed -i "s#PASSWORD_VALUE#changeit#g" reporting/database/reporting/sql/db-jenkins-integration.sql
      sed -i "s#FOLDER_VALUE##g" reporting/database/reporting/sql/db-jenkins-integration.sql
    fi

    if [[ $ZBR_MCLOUD_ENABLED -eq 1 ]]; then
        mcloud/zebrunner.sh setup

      # update reporting-mcloud integration script
      #TODO: generate secure htpasswd for mcloud
      cp reporting/database/reporting/sql/db-mcloud-integration.sql.original reporting/database/reporting/sql/db-mcloud-integration.sql
      sed -i "s#URL_VALUE#$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/mcloud/wd/hub#g" reporting/database/reporting/sql/db-mcloud-integration.sql
      sed -i "s#USER_VALUE#demo#g" reporting/database/reporting/sql/db-mcloud-integration.sql
      sed -i "s#PASSWORD_VALUE#demo#g" reporting/database/reporting/sql/db-mcloud-integration.sql
    fi

    if [[ $ZBR_SELENOID_ENABLED -eq 1 ]]; then
        selenoid/zebrunner.sh setup

      # update reporting-mcloud integration script
      #TODO: generate secure htpasswd for selenoid
      cp reporting/database/reporting/sql/db-selenium-integration.sql.original reporting/database/reporting/sql/db-selenium-integration.sql
      sed -i "s#URL_VALUE#$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/selenoid/wd/hub#g" reporting/database/reporting/sql/db-selenium-integration.sql
      sed -i "s#USER_VALUE#demo#g" reporting/database/reporting/sql/db-selenium-integration.sql
      sed -i "s#PASSWORD_VALUE#demo#g" reporting/database/reporting/sql/db-selenium-integration.sql
    fi

    # export all ZBR* variables to save user input
    export_settings
  }

  shutdown() {
    rm nginx/conf.d/default.conf
    rm backup/settings.env

    rm -f reporting/database/reporting/sql/db-jenkins-integration.sql
    rm -f reporting/database/reporting/sql/db-mcloud-integration.sql
    rm -f reporting/database/reporting/sql/db-selenium-integration.sql

    jenkins/zebrunner.sh shutdown
    reporting/zebrunner.sh shutdown
    sonarqube/zebrunner.sh shutdown
    mcloud/zebrunner.sh shutdown
    selenoid/zebrunner.sh shutdown
    docker-compose down -v

  }

  start() {
    if [ ! -f ./nginx/conf.d/default.conf ]; then
      printf 'WARNING! You have to setup services in advance! For example:\n ./zebrunner.sh setup\n\n' "$(basename "$0")" >&2
      exit -1
    fi

    print_banner

    # create infra network only if not exist
    docker network inspect infra >/dev/null 2>&1 || docker network create infra

    #-------------- START EVERYTHING ------------------------------
    selenoid/zebrunner.sh start
    mcloud/zebrunner.sh start
    jenkins/zebrunner.sh start
    reporting/zebrunner.sh start
    sonarqube/zebrunner.sh start

    docker-compose up -d
  }

  stop() {
    jenkins/zebrunner.sh stop
    reporting/zebrunner.sh stop
    sonarqube/zebrunner.sh stop
    mcloud/zebrunner.sh stop
    selenoid/zebrunner.sh stop
    docker-compose stop
  }

  down() {
    jenkins/zebrunner.sh down
    reporting/zebrunner.sh down
    sonarqube/zebrunner.sh down
    mcloud/zebrunner.sh down
    selenoid/zebrunner.sh down
    docker-compose down
  }

  backup() {
    print_banner
    stop

    cp ./nginx/conf.d/default.conf ./nginx/conf.d/default.conf.bak
    cp backup/settings.env backup/settings.env.bak
    if [[ -f reporting/database/reporting/sql/db-jenkins-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-jenkins-integration.sql reporting/database/reporting/sql/db-jenkins-integration.sql.bak
    fi
    if [[ -f reporting/database/reporting/sql/db-mcloud-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-mcloud-integration.sql reporting/database/reporting/sql/db-mcloud-integration.sql.bak
    fi
    if [[ -f reporting/database/reporting/sql/db-selenium-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-selenium-integration.sql reporting/database/reporting/sql/db-selenium-integration.sql.bak
    fi


    jenkins/zebrunner.sh backup
    reporting/zebrunner.sh backup
    sonarqube/zebrunner.sh backup
    mcloud/zebrunner.sh backup
    selenoid/zebrunner.sh backup
  }

  restore() {
    print_banner

    stop
    cp ./nginx/conf.d/default.conf.bak ./nginx/conf.d/default.conf
    cp backup/settings.env.bak backup/settings.env
    if [[ -f reporting/database/reporting/sql/db-jenkins-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-jenkins-integration.sql.bak reporting/database/reporting/sql/db-jenkins-integration.sql
    fi
    if [[ -f reporting/database/reporting/sql/db-mcloud-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-mcloud-integration.sql.bak reporting/database/reporting/sql/db-mcloud-integration.sql
    fi
    if [[ -f reporting/database/reporting/sql/db-selenium-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-selenium-integration.sql.bak reporting/database/reporting/sql/db-selenium-integration.sql
    fi

    jenkins/zebrunner.sh restore
    reporting/zebrunner.sh restore
    sonarqube/zebrunner.sh restore
    mcloud/zebrunner.sh restore
    selenoid/zebrunner.sh restore
    down
  }

  enableLayer() {
    local layer=$1
    local message=$2
    local isEnabled=$3

    echo
    confirm "$message" "Enable?" "$isEnabled"
    if [[ $? -eq 1 ]]; then
      # enable component/layer
      if [[ -f $layer/.disabled ]]; then
        rm $layer/.disabled
      fi
      return 1
    else
      disableLayer $layer
      return 0
    fi
  }

  disableLayer() {
    # disbale component/layer
    echo > $1/.disabled
    return 0
  }

  set_global_settings() {
    # Setup global settings: protocol, hostname and port
    echo "Zebrunner Global Settings"
    local is_confirmed=0
    if [[ -z $ZBR_HOSTNAME ]]; then
      ZBR_HOSTNAME=$HOSTNAME
    fi

    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Protocol [$ZBR_PROTOCOL]: " local_protocol
      if [[ ! -z $local_protocol ]]; then
        ZBR_PROTOCOL=$local_protocol
      fi

      read -p "Fully qualified domain name (ip) [$ZBR_HOSTNAME]: " local_hostname
      if [[ ! -z $local_hostname ]]; then
        ZBR_HOSTNAME=$local_hostname
      fi

      read -p "Port [$ZBR_PORT]: " local_port
      if [[ ! -z $local_port ]]; then
        ZBR_PORT=$local_port
      fi

      confirm "Zebrunner URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_PROTOCOL=$ZBR_PROTOCOL
    export ZBR_HOSTNAME=$ZBR_HOSTNAME
    export ZBR_PORT=$ZBR_PORT

  }

  set_reporting_settings() {
    # Collect reporting settings
    ## Crypto token and salt
    echo
    echo "Reporting Service Crypto:"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Signin token secret (randomized base64 encoded string) [$ZBR_TOKEN_SIGNING_SECRET]: " local_token
      if [[ ! -z $local_token ]]; then
        ZBR_TOKEN_SIGNING_SECRET=$local_token
      fi

      read -p "Crypto salt (randomized string) [$ZBR_CRYPTO_SALT]: " local_salt
      if [[ ! -z $local_salt ]]; then
        ZBR_CRYPTO_SALT=$local_salt
      fi

      echo "Signin token secret=$ZBR_TOKEN_SIGNING_SECRET"
      echo "Crypto Salt=$ZBR_CRYPTO_SALT"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_TOKEN_SIGNING_SECRET=$ZBR_TOKEN_SIGNING_SECRET
    export ZBR_CRYPTO_SALT=$ZBR_CRYPTO_SALT


    ## iam-service posgtres
    local is_confirmed=0
    echo
    echo "IAM - Identity and Access Management service"
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "IAM postgres password [$ZBR_IAM_POSTGRES_PASSWORD]: " local_iam_postgres_password
      if [[ ! -z $local_iam_postgres_password ]]; then
        ZBR_IAM_POSTGRES_PASSWORD=$local_iam_postgres_password
      fi

      echo "Identity and Access Management service postgres password: $ZBR_IAM_POSTGRES_PASSWORD"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_IAM_POSTGRES_PASSWORD=$ZBR_IAM_POSTGRES_PASSWORD


    ## reporting posgtres instance
    echo
    echo "Reporting Service database"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Reporting postgres password [$ZBR_POSTGRES_PASSWORD]: " local_postgres_password
      if [[ ! -z $local_postgres_password ]]; then
        ZBR_POSTGRES_PASSWORD=$local_postgres_password
      fi

      echo "Reporting Service postgres password: $ZBR_POSTGRES_PASSWORD"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_POSTGRES_PASSWORD=$ZBR_POSTGRES_PASSWORD


    ## email-service (smtp)
    echo
    echo "Reporting smtp email settings"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Host [$ZBR_SMTP_HOST]: " local_smtp_host
      if [[ ! -z $local_smtp_host ]]; then
        ZBR_SMTP_HOST=$local_smtp_host
      fi

      read -p "Port [$ZBR_SMTP_PORT]: " local_smtp_port
      if [[ ! -z $local_smtp_port ]]; then
        ZBR_SMTP_PORT=$local_smtp_port
      fi

      read -p "Sender email [$ZBR_SMTP_EMAIL]: " local_smtp_email
      if [[ ! -z $local_smtp_email ]]; then
        ZBR_SMTP_EMAIL=$local_smtp_email
      fi

      read -p "User [$ZBR_SMTP_USER]: " local_smtp_user
      if [[ ! -z $local_smtp_user ]]; then
        ZBR_SMTP_USER=$local_smtp_user
      fi

      read -p "Password [$ZBR_SMTP_PASSWORD]: " local_smtp_password
      if [[ ! -z $local_smtp_password ]]; then
        ZBR_SMTP_PASSWORD=$local_smtp_password
      fi

      echo "host=$ZBR_SMTP_HOST:$ZBR_SMTP_PORT"
      echo "email=$ZBR_SMTP_EMAIL"
      echo "user=$ZBR_SMTP_USER"
      echo "password=$ZBR_SMTP_PASSWORD"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_SMTP_HOST=$ZBR_SMTP_HOST
    export ZBR_SMTP_PORT=$ZBR_SMTP_PORT
    export ZBR_SMTP_EMAIL=$ZBR_SMTP_EMAIL
    export ZBR_SMTP_USER=$ZBR_SMTP_USER
    export ZBR_SMTP_PASSWORD=$ZBR_SMTP_PASSWORD


    ## reporting rabbitmq
    echo
    echo "Reporting Rabbitmq - messaging queue credentials"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Rabbitmq user [$ZBR_RABBITMQ_USER]: " local_rabbitmq_user
      if [[ ! -z $local_rabbitmq_user ]]; then
        ZBR_RABBITMQ_USER=$local_rabbitmq_user
      fi

      read -p "Rabbitmq password [$ZBR_RABBITMQ_PASSWORD]: " local_rabbitmq_password
      if [[ ! -z $local_rabbitmq_password ]]; then
        ZBR_RABBITMQ_PASSWORD=$local_rabbitmq_password
      fi

      echo "Rabbitmq credentials=$ZBR_RABBITMQ_USER/$ZBR_RABBITMQ_PASSWORD"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_RABBITMQ_USER=$ZBR_RABBITMQ_USER
    export ZBR_RABBITMQ_PASSWORD=$ZBR_RABBITMQ_PASSWORD

    ## reporting redis
    echo
    echo "Reporting Redis - in-memory cache database"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Redis password [$ZBR_REDIS_PASSWORD]: " local_redis_password
      if [[ ! -z $local_redis_password ]]; then
        ZBR_REDIS_PASSWORD=$local_redis_password
      fi

      echo
      echo "Redis password=$ZBR_REDIS_PASSWORD"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_REDIS_PASSWORD=$ZBR_REDIS_PASSWORD

    ## test launchers git integration
    echo
    echo "Reporting Test Launchers git integration"
    local is_confirmed=0
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Git host [$ZBR_GITHUB_HOST]: " local_git
      if [[ ! -z $local_git ]]; then
        ZBR_GITHUB_HOST=$local_git
      fi

      read -p "Client ID [$ZBR_GITHUB_CLIENT_ID]: " local_client_id
      if [[ ! -z $local_client_id ]]; then
        ZBR_GITHUB_CLIENT_ID=$local_client_id
      fi

      read -p "client Secret [$ZBR_GITHUB_CLIENT_SECRET]: " local_secret_id
      if [[ ! -z $local_secret_id ]]; then
        ZBR_GITHUB_CLIENT_SECRET=$local_secret_id
      fi

      echo
      echo "Git integration"
      echo "Host: ${ZBR_GITHUB_HOST}"
      echo "Client ID: ${ZBR_GITHUB_CLIENT_ID}"
      echo "Client Secret: ${ZBR_GITHUB_CLIENT_SECRET}"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_GITHUB_HOST=$ZBR_GITHUB_HOST
    export ZBR_GITHUB_CLIENT_ID=$ZBR_GITHUB_CLIENT_ID
    export ZBR_GITHUB_CLIENT_SECRET=$ZBR_GITHUB_CLIENT_SECRET

  }

  set_minio_storage_settings() {
    ## Minio S3 compatible storage 
    local is_confirmed=0
    echo
    echo "Minio S3 compatible storage"
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Minio access key [$ZBR_ACCESS_KEY]: " local_minio_access_key
      if [[ ! -z $local_minio_access_key ]]; then
        ZBR_ACCESS_KEY=$local_minio_access_key
      fi

      read -p "Minio secret key [$ZBR_SECRET_KEY]: " local_minio_secret_key
      if [[ ! -z $local_minio_secret_key ]]; then
        ZBR_SECRET_KEY=$local_minio_secret_key
      fi

      echo "Minio storage credentials: $ZBR_ACCESS_KEY/$ZBR_SECRET_KEY"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_ACCESS_KEY=$ZBR_ACCESS_KEY
    export ZBR_SECRET_KEY=$ZBR_SECRET_KEY
  }

  set_aws_storage_settings() {
    ## AWS S3 storage
    local is_confirmed=0
    echo
    echo "AWS S3 storage"
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Region [$ZBR_REGION]: " local_region
      if [[ ! -z $local_region ]]; then
        ZBR_REGION=$local_region
      fi

      read -p "Bucket [$ZBR_BUCKET]: " local_bucket
      if [[ ! -z $local_bucket ]]; then
        ZBR_BUCKET=$local_bucket
      fi

      read -p "Access key [$ZBR_ACCESS_KEY]: " local_minio_access_key
      if [[ ! -z $local_minio_access_key ]]; then
        ZBR_ACCESS_KEY=$local_minio_access_key
      fi

      read -p "Secret key [$ZBR_SECRET_KEY]: " local_minio_secret_key
      if [[ ! -z $local_minio_secret_key ]]; then
        ZBR_SECRET_KEY=$local_minio_secret_key
      fi

      echo "Region: $ZBR_REGION"
      echo "Bucket: $ZBR_BUCKET"
      echo "Access key: $ZBR_ACCESS_KEY"
      echo "Secret key: $ZBR_SECRET_KEY"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_REGION=$ZBR_REGION
    export ZBR_BUCKET=$ZBR_BUCKET
    export ZBR_ACCESS_KEY=$ZBR_ACCESS_KEY
    export ZBR_SECRET_KEY=$ZBR_SECRET_KEY

    # for AWS S3 integration S3_ENDPOINT should be blank!
    export ZBR_S3_ENDPOINT=
  }

  export_settings() {
    export -p | grep "ZBR" > backup/settings.env
  }

  random_string() {
    cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 48; echo
  }

  confirm() {
    local message=$1
    local question=$2
    local isEnabled=$3

    if [[ "$isEnabled" == "1" ]]; then
      isEnabled="y"
    fi
    if [[ "$isEnabled" == "0" ]]; then
      isEnabled="n"
    fi

    while true; do
      if [[ ! -z $message ]]; then
        echo "$message"
      fi

      read -p "$question Yes/No [$isEnabled]:" response
      if [[ -z $response ]]; then
        if [[ "$isEnabled" == "y" ]]; then
          return 1
        fi
        if [[ "$isEnabled" == "n" ]]; then
          return 0
        fi
      fi

      if [[ "$response" == "y" || "$response" == "Y" ]]; then
        return 1
      fi

      if [[ "$response" == "n" ||  "$response" == "N" ]]; then
        return 0
      fi

      echo "Please answer y (yes) or n (no)."
      echo
    done
  }

  echo_warning() {
    echo "
      WARNING! $1"
  }

  echo_telegram() {
    echo "
      For more help join telegram channel: https://t.me/zebrunner
      "
  }

  echo_help() {
    echo "
      Usage: ./zebrunner.sh [option]
      Flags:
          --help | -h    Print help
      Arguments:
          setup          Setup Zebrunner Server (Community Edition)
      	  start          Start container
      	  stop           Stop and keep container
      	  restart        Restart container
      	  down           Stop and remove container
      	  shutdown       Stop and remove container, clear volumes
      	  backup         Backup container
      	  restore        Restore container"
      echo_telegram
      exit 0
  }

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ${BASEDIR}

case "$1" in
    setup)
        setup
        ;;
    start)
	start
        ;;
    stop)
        stop
        ;;
    restart)
        down
        start
        ;;
    down)
        down
        ;;
    shutdown)
        shutdown
        ;;
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    *)
        echo "Invalid option detected: $1"
        echo_help
        exit 1
        ;;
esac

