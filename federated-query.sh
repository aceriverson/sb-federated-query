BBLACK='\033[1;30m'
BBLUE='\033[1;34m'
NC='\033[0m'

export GUID=$1
export AWS_KEY=$2
export AWS_SECRET=$3

if [ $# -ne 3 ]
  then
    echo "Usage: bash federated-query.sh [GUID] [AWS_KEY] [AWS_SECRET]"
    exit 1
fi

# Deploy postgres
echo -e "${BBLACK}Deploying ${BBLUE}Postgres Database${NC}"
oc apply -f postgres.yaml

# Copy license and deploy secret
echo -e "${BBLACK}Configuring ${BBLUE}Starburst License${NC}"

oc exec deploy/coordinator -n starburst -- \
  cat starburst-license-json/starburstdata.license \
  > starburstdata.license

oc create secret generic starburst-license -n starburst \
  --from-file starburstdata.license

# Add postgres/s3 catalogs
echo -e "${BBLACK}Configuring ${BBLUE}Starburst Catalogs${NC}"
rm -f catalog-patch.yaml temp.yaml

( echo "cat <<EOF >catalog-patch.yaml";
  cat catalog-template.yaml;
) >temp.yaml
. temp.yaml

oc patch starburstenterprise starburst-enterprise \
  --type merge \
  --patch-file catalog-patch.yaml \
  -n starburst

rm -f catalog-patch.yaml temp.yaml

# Upload customers to s3
echo -e "${BBLACK}Uploading ${BBLUE}Customers to S3${NC}"
aws s3 mb s3://federated-query-${GUID}

aws s3 cp ./data/customers.csv s3://federated-query-${GUID}

# Upload transactions to postgres
echo -e "${BBLACK}Waiting for ${BBLUE}Postgres Rollout${NC}"
oc rollout status deployment postgres -n postgres

echo -e "${BBLACK}Uploading ${BBLUE}Transactions to Postgres${NC}"
oc cp ./data/transactions.csv \
  $(oc get pods -n postgres -o 'jsonpath={.items[0].metadata.name}'):/temp \
  -n postgres

# Make sure postgres is running, in future replace with pg_isready in loop

echo -e "${BBLACK}Parsing ${BBLUE}Transactions${NC}"
oc exec deploy/postgres -n postgres -- psql postgres postgres -c \
    "CREATE TABLE transactions (
        id SERIAL,
        User_ID INTEGER,
        Product_ID VARCHAR(9),
        Purchase BIGINT,
        PRIMARY KEY (id)
    );"

oc exec deploy/postgres -n postgres -- psql postgres postgres -c \
    "SELECT *
     FROM pg_catalog.pg_tables
     WHERE schemaname != 'pg_catalog'
         AND schemaname != 'information_schema';"

oc exec deploy/postgres -n postgres -- psql postgres postgres -c \
    "COPY transactions(User_ID, Product_ID, Purchase)
     FROM '/temp/transactions.csv'
     DELIMITER ','
     CSV HEADER;"

# Share Starburst Web UI route
echo -e "${BBLUE}Starburst is ready:${NC}"
oc get routes -n starburst -o 'jsonpath={.items[0].spec.host}'