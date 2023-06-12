if [ $# -ne 1 ]
  then
    echo "Usage: bash federated-query-reset.sh [GUID]"
    exit 1
fi

oc delete project postgres

oc delete secret starburst-license -n starburst

# TODO: Unpatch starburst-enterprise

aws s3 rb s3://federated-query-$1 --force