# Homogenous Migration for PostgreSQL to CloudSQL/AlloyDB using Migration Utility

This tool automates the migration of PostgreSQL databases to Google Cloud's CloudSQL for PostgreSQL or AlloyDB for PostgreSQL using Google Cloud's Database Migration Service (DMS) and provides validation capabilities.

## Overview

The scripts in this repository streamline the end-to-end migration process, handling tasks such as:

* **DMS Setup:** Creating necessary connection profiles and migration jobs.
* **Target Environment Provisioning:** (Optional) Setting up a dedicated Compute Engine instance for data validation.
* **Pre- and Post-Migration Validations:** Performing automated data validation using the `google-pso-data-validator` tool to ensure data integrity.
* **User and Permission Migration:** Extracting and applying user and permission definitions.

## Key Components

The repository includes the following main components:

* **`run_dms.sh`:** This script orchestrates the Database Migration Service (DMS) setup, including connection profile creation and migration job execution.
* **`prevalidations.sh`:** This script is executed on a designated VM to perform pre-cutover data validations. It installs the necessary tools (PostgreSQL client, `google-pso-data-validator`) and runs validation checks. It also extracts user/role definitions, permissions, and schema ownership information from the source database.
* **`postvalidations.sh`:** Similar to `prevalidations.sh`, this script is executed on a designated VM to perform post-cutover data validation.
* **`setup_validations.sh`:** This script sets up the environment for data validation, including creating a BigQuery dataset and table to store validation results, and optionally provisioning a Compute Engine instance to run the validation scripts.
* **`migration.config`:** This configuration file stores variables required for the migration process, such as database connection details, project IDs, and instance names.

## Prerequisites

Before using this tool, ensure you have the following:

* **Google Cloud Project:** You need an active Google Cloud Project.
* **Enabled APIs:** The following Google Cloud APIs must be enabled in your project:
    * Database Migration Service API
    * Compute Engine API (if using VM provisioning)
    * BigQuery API (if using data validation)
    * Cloud SQL API (if migrating to Cloud SQL)
    * AlloyDB API (if migrating to AlloyDB)
* **`gcloud` CLI:** The Google Cloud SDK (`gcloud` CLI) must be installed and configured. If you are using a GCP VM, gcloud is pre-installed.
* **PostgreSQL Database:** You need access to the source PostgreSQL database you intend to migrate.
* **Network Connectivity:** Ensure network connectivity between your source PostgreSQL database and Google Cloud. This might involve VPC peering, VPN, or other network configurations.
* **Permissions:** Ensure you have the necessary IAM permissions to create resources in your Google Cloud project (e.g., Compute Engine instances, BigQuery datasets, DMS migration jobs).

## Setup and Configuration

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/itsabhisharma23/alloydb-migration-utility.git
    ```
2.  **Configure `migration.config`:**
    * Carefully edit the `migration.config` file to provide the specific details of your source and destination databases, Google Cloud project, and other environment settings.  **This is the most critical step.** Pay close attention to:
        * Project IDs and regions
        * Source and destination database connection details (host, port, user, passwords)
        * DMS migration job names and network settings
        * Data validation VM settings (if applicable)
        * BigQuery dataset and connection names
3.  **Grant Execute Permissions:**
    ```bash
    chmod +x *.sh
    ```

## Usage

### 1.  Run the DMS Migration (`run_dms.sh`)

This script handles the core migration process using DMS. This will create connection profile and DMS job based on the config provided in the 'migration.config'. The script will also trigger the DMS job and wait for it to be in running state. 

```bash
./run_dms.sh
