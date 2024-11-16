#!/bin/bash

# Function to install dependencies
install_dependencies() {
  echo "Checking and installing dependencies..."

  # Update package list
  sudo apt-get update

  # Install Duplicity
  if ! command -v duplicity &> /dev/null; then
    echo "Installing Duplicity..."
    sudo apt-get install -y duplicity
  fi

  # Install Python pip
  if ! command -v pip &> /dev/null; then
    echo "Installing pip..."
    sudo apt-get install -y python3-pip
  fi

  # Install boto3 for S3-compatible services
  if ! python3 -c "import boto3" &> /dev/null; then
    echo "Installing boto3..."
    pip install boto3
  fi

  # Install google-cloud-storage for Google Cloud Storage
  if ! python3 -c "import google.cloud.storage" &> /dev/null; then
    echo "Installing google-cloud-storage..."
    pip install google-cloud-storage
  fi

  # Install b2sdk for Backblaze B2
  if ! python3 -c "import b2sdk" &> /dev/null; then
    echo "Installing b2sdk..."
    pip install b2sdk
  fi

  # Install azure-storage-blob for Azure Blob Storage
  if ! python3 -c "import azure.storage.blob" &> /dev/null; then
    echo "Installing azure-storage-blob..."
    pip install azure-storage-blob
  fi

  # Install ibm-cos-sdk for IBM Cloud Object Storage
  if ! python3 -c "import ibm_boto3" &> /dev/null; then
    echo "Installing ibm-cos-sdk..."
    pip install ibm-cos-sdk
  fi

  echo "All dependencies are installed."
}

# Run the function
install_dependencies
