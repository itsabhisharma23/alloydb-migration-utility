#!/bin/bash

CONFIG_FILE="migration.config"

GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

# Source the banner script (assuming it exists in the same directory)
if [ -f "./banner.sh" ]; then
  source ./banner.sh
else
  echo "Warning: banner not found."
fi

# Function to create source profile
create_source_profile() {
  echo "${YELLOW}Creating source profile...${NC}"
  gcloud database-migration connection-profiles create postgresql "$SOURCE_PROFILE_NAME" \
      --region="$REGION" \
      --display-name="$SOURCE_PROFILE_NAME" \
      --username="$SOURCE_USER" \
      --host="$SOURCE_HOST" \
      --port="$SOURCE_PORT" \
      --prompt-for-password \
      --project="$PROJECT_ID"

  # Check if the profile creation was successful
  if [ $? -eq 0 ]; then
    echo "${GREEN}Connection profile \"${BOLD}$SOURCE_PROFILE_NAME${NC}${GREEN}\" created successfully.${NC}"
  else
    echo "${RED}Error: Failed to create connection profile \"${BOLD}$SOURCE_PROFILE_NAME${NC}${RED}\".${NC}"
    exit 1
  fi
}

# Function to create target profile
create_target_profile() {
  if (( target_type_name == "AlloyDB" )); then
      echo "${YELLOW}Creating destination profile for AlloyDB...${NC}"
      gcloud database-migration connection-profiles create postgresql "$DESTINATION_PROFILE_NAME" \
      --region="$REGION" \
      --display-name="$DESTINATION_PROFILE_NAME" \
      --alloydb-cluster="$DESTINATION_ALLOYDB" \
      --username="$DESTINATION_USER" \
      --host="$DESTINATION_HOST" \
      --port="$DESTINATION_PORT" \
      --prompt-for-password \
      --project="$PROJECT_ID"
  else
      echo "${YELLOW}Creating destination profile for CloudSQL...${NC}"
      gcloud database-migration connection-profiles create postgresql "$DESTINATION_PROFILE_NAME" \
      --region="$REGION" \
      --display-name="$DESTINATION_PROFILE_NAME" \
      --cloudsql-instance="$DESTINATION_CloudSQL_INSTANCE_NAME" \
      --username="$DESTINATION_USER" \
      --host="$DESTINATION_HOST" \
      --port="$DESTINATION_PORT" \
      --prompt-for-password \
      --project="$PROJECT_ID"
  fi

  # Check if the profile creation was successful
  if [ $? -eq 0 ]; then
    echo "${GREEN}Connection profile \"${BOLD}$DESTINATION_PROFILE_NAME${NC}${GREEN}\" created successfully.${NC}"
  else
    echo "${RED}Error: Failed to create connection profile \"${BOLD}$DESTINATION_PROFILE_NAME${NC}${RED}\".${NC}"
    exit 1
  fi
}

# Function to create DMS job
create_dms_job() {
  echo "${YELLOW}Creating database migration job...${NC}"

  # Print Notes:
  echo ""
  echo "${BOLD}Note: By Default the tool uses VPC peering.${NC}"
  echo "${BOLD}For Reverse-SSH Proxy provide the additional properties of --vm, --vm-ip, --vm-port and --vpc in the migration.config file\n${NC}"

  if [ -v VM_NAME ]; then
      gcloud database-migration migration-jobs create "$MIGRATION_JOB_NAME" \
      --region="$REGION" \
      --type="$MIGRATION_TYPE" \
      --source="$SOURCE_PROFILE_NAME" \
      --destination="$DESTINATION_PROFILE_NAME" \
      --project="$PROJECT_ID" --vm="$VM_NAME" --vm-ip="$VM_IP_ADDRESS" --vm-port="$VM_PORT" --vpc="$VPC"
  else
      gcloud database-migration migration-jobs create "$MIGRATION_JOB_NAME" \
      --region="$REGION" \
      --type="$MIGRATION_TYPE" \
      --source="$SOURCE_PROFILE_NAME" \
      --destination="$DESTINATION_PROFILE_NAME" \
      --peer-vpc="$MIGRATION_NETWORK_FQDN" \
      --project="$PROJECT_ID" # --vm=$VM_NAME --vm-ip=$VM_IP_ADDRESS --vm-port=$VM_PORT --vpc=$VPC
  fi

  # Check if the dms job creation was successful
  if [ $? -eq 0 ]; then
    echo "${GREEN}DMS job $MIGRATION_JOB_NAME created successfully.${NC}"
  else
    echo "${RED}Error: Failed to create DMS job $MIGRATION_JOB_NAME.${NC}"
    exit 1
  fi

  echo "${YELLOW}Waiting for DMS job to be in ready state...${NC}"

  # wait for DMS creation
  while true; do
      STATUS=$(gcloud database-migration migration-jobs describe "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID" --format='value(state)')

      if [[ "$STATUS" == "NOT_STARTED" ]]; then
          echo "Migration job '$MIGRATION_JOB_NAME' has changed state to: $STATUS"
          break  # Exit the loop when the state is no longer NOT_STARTED
      else
          echo "Migration job '$MIGRATION_JOB_NAME' is still not ready. Waiting..."
          sleep 10  # Wait for 10 seconds before checking again
      fi
  done

  if (( target_type_name == "AlloyDB" )); then
    # Demote the destination before starting the job
    gcloud database-migration migration-jobs demote-destination "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID"
    echo ""
    echo "${YELLOW}Waiting for destination to be in demoted state...${NC}"
    # wait for destination demotion

    while true; do
        STATUS=$(gcloud alloydb clusters describe "$DESTINATION_ALLOYDB" --region="$REGION" --project="$PROJECT_ID" --format="value(state)")

        if [[ "$STATUS" == "BOOTSTRAPPING" ]]; then
            echo "${GREEN}${BOLD}Destination is demoted.${NC}"
            break  # Exit the loop when the state is no longer NOT_STARTED
        else
            echo "Waiting for destination to be in demoted state..."
            sleep 10  # Wait for 10 seconds before checking again
        fi
    done
  else
    # Demote the destination before starting the job
    gcloud database-migration migration-jobs demote-destination "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID"
    while true; do
        MASTER_TYPE=$(gcloud sql instances describe "$DESTINATION_CloudSQL_INSTANCE_NAME" --project="$PROJECT_ID" --format='value(instanceType)')
        if [[ "$MASTER_TYPE" == "READ_REPLICA_INSTANCE" ]]; then
            echo "${GREEN}${BOLD}Destination is demoted.${NC}"
            break  # Exit the loop when the state is no longer NOT_STARTED
        else
            echo "Waiting for destination to be in demoted state..."
            sleep 10  # Wait for 10 seconds before checking again
        fi
    done
  fi

  echo ""
  echo "${BOLD}Migration Job details${NC}"
  gcloud database-migration migration-jobs describe "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID"
  echo ""
  echo "${YELLOW}Starting the DMS job...${NC}"

  #Start DMS Job
  gcloud database-migration migration-jobs start "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID"

  echo ""
  while true; do
      STATUS=$(gcloud database-migration migration-jobs describe "$MIGRATION_JOB_NAME" --region="$REGION" --project="$PROJECT_ID" --format='value(state)')

      if [[ "$STATUS" == "FAILED" ]]; then
          echo "${RED}Migration job '$MIGRATION_JOB_NAME' has FAILED. Please check the job on the console.${NC}"
          break  # Exit the loop when the state is no longer NOT_STARTED
      elif [[ "$STATUS" == "RUNNING" ]]; then
          echo "${BOLD}Migration job '$MIGRATION_JOB_NAME' is running. Please check the job on the console.${NC}"
          break
      else
          echo "Migration job '$MIGRATION_JOB_NAME' has started. Waiting to be in running state..."
          sleep 10  # Wait for 10 seconds before checking again
      fi
  done
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-profile)
      ACTION="source-profile"
      shift
      ;;
    --target-profile)
      ACTION="target-profile"
      shift
      ;;
    --dms-only)
      ACTION="dms-only"
      shift
      ;;
    *)
      echo "Error: Unknown option '$1'"
      exit 1
      ;;
  esac
done

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
  echo "\nLoading your configuration from $CONFIG_FILE"
  source "$CONFIG_FILE"
else
  echo "\nWarning: Configuration file '$CONFIG_FILE' not found. "
fi

# Determine which actions to perform based on arguments
if [[ -z "$ACTION" ]]; then
  # If no arguments are provided, run the full script interactively
  echo -e "\n\nSelect the source PostgreSQL type:\n"
  echo "1. On-premise"
  echo "2. AWS"
  echo "3. Azure"
  read -p "Enter your choice (1-3): " source_type

  case "$source_type" in
    1) source_type_name="On-premise";;
    2) source_type_name="AWS";;
    3) source_type_name="Azure";;
    *) echo -e "\nError: Invalid source type selected. Please enter a number between 1 and 3."; exit 1;;
  esac

  echo -e "\n\nSelect the target type:\n"
  echo "1. AlloyDB"
  echo "2. CloudSQL"
  read -p "Enter your choice (1-2): " target_type

  case "$target_type" in
    1) target_type_name="AlloyDB";;
    2) target_type_name="CloudSQL";;
    *) echo -e "\nError: Invalid target type selected. Please enter either 1 or 2."; exit 1;;
  esac

  echo ""
  echo "-------------------------------------------------------------------------------------"
  echo "You are about to migrate databases from ${GREEN}$source_type_name${NC} to ${GREEN}$target_type_name${NC}."
  echo "-------------------------------------------------------------------------------------"
  echo ""
  echo ""
  echo "Note: You can run migration assessment to check compatibility between Source and Target databases."
  echo "      Run migration assessment on a machine where your source database is accessible."
  read -p "${BOLD}Do you want to run Migration Assessment for Postgres?${NC} : y/n  " is_migration_assessment
  echo ""
  is_migration_assessment="${is_migration_assessment,,}"
  if [[ "$is_migration_assessment" == "y" ]]; then
    echo "${YELLOW}${BOLD}Running Migration Assessment...${NC}"
    source "migration_assessment.sh"
    echo ""
    echo ""
    read -p "${BOLD}Do you want to continue with Database Migration?${NC} : y/n  " continue_dms
    continue_dms="${continue_dms,,}"
    if [[ "$continue_dms" != "y" ]]; then
      echo "${BOLD}You chose not to run Database Migration at this point. Exiting the tool.${NC}"
      exit 0
    fi
  else
    echo "${BOLD}Skipping Migration Assessment...${NC}"
  fi

  create_source_profile
  create_target_profile
  create_dms_job

elif [[ "$ACTION" == "source-profile" ]]; then
  # Prompt for source type if not already loaded from config
  if [[ -z "$source_type_name" ]]; then
    echo -e "\n\nSelect the source PostgreSQL type:\n"
    echo "1. On-premise"
    echo "2. AWS"
    echo "3. Azure"
    read -p "Enter your choice (1-3): " source_type
    case "$source_type" in
      1) source_type_name="On-premise";;
      2) source_type_name="AWS";;
      3) source_type_name="Azure";;
      *) echo -e "\nError: Invalid source type selected. Please enter a number between 1 and 3."; exit 1;;
    esac
  fi
  create_source_profile

elif [[ "$ACTION" == "target-profile" ]]; then
  # Prompt for target type if not already loaded from config
  if [[ -z "$target_type_name" ]]; then
    echo -e "\n\nSelect the target type:\n"
    echo "1. AlloyDB"
    echo "2. CloudSQL"
    read -p "Enter your choice (1-2): " target_type
    case "$target_type" in
      1) target_type_name="AlloyDB";;
      2) target_type_name="CloudSQL";;
      *) echo -e "\nError: Invalid target type selected. Please enter either 1 or 2."; exit 1;;
    esac
  fi
  create_target_profile

elif [[ "$ACTION" == "dms-only" ]]; then
  create_dms_job
fi

exit 0