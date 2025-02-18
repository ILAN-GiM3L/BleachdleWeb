pipeline {
    agent any

    environment {
        // Add /usr/local/bin to the PATH so Jenkins can access Docker
        PATH = "/usr/local/bin:/opt/homebrew/bin:$PATH"
        // Environment variables for Docker Hub, DB, and project details
        DOCKERHUB_REPO = 'ilangimel/bleachdle-web-app'
        DOCKERHUB_USERNAME = credentials('DOCKERHUB_USERNAME') // Secret for Docker Hub username
        DOCKERHUB_PASSWORD = credentials('DOCKERHUB_PASSWORD') // Secret for Docker Hub password
        IMAGE_NAME = 'ilangimel/bleachdle-web-app' // Update with your image name
        VERSION = "${BUILD_NUMBER}" // Build versioning using Jenkins build number


    }

    stages {
        // Stage 1: Clean Workspace
        stage('Clean Workspace') {
            steps {
                cleanWs()  // Cleans up the workspace to ensure a fresh build environment
            }
        }

        // Stage 2: Clone Repository
        stage('Clone Repository') {
            steps {
                script {
                    checkout([$class: 'GitSCM',
                        branches: [[name: '*/main']],  // Checkout the main branch
                        userRemoteConfigs: [[
                            url: 'https://github.com/Ilan-Gimel/BleachdleWeb-git.git', // Replace with your repo URL
                            credentialsId: 'Github-cred'  // Make sure GitHub credentials are set in Jenkins
                        ]]
                    ])
                }
            }
        }


        // // Stage 3: Login to Docker Hub
        // stage('Login to Docker Hub') {
        //     steps {
        //         script {
        //             // Fetch the secret text credentials for username and password
        //             withCredentials([string(credentialsId: 'DOCKERHUB_USERNAME', variable: 'DOCKER_USERNAME'),
        //                              string(credentialsId: 'DOCKERHUB_PASSWORD', variable: 'DOCKER_PASSWORD')]) {
        //                 // Use the credentials directly in docker login (using full path to docker)
        //                 sh '''
        //                     echo "Logging into Docker Hub"
        //                     echo $DOCKER_PASSWORD | docker login --username $DOCKER_USERNAME --password-stdin
        //                 '''
        //             }
        //         }
        //     }
        // }

        // // Stage 4: Build and Push Docker Image
        // stage('Build and Push Docker Image') {
        //     steps {
        //         script {
        //             dir("${WORKSPACE}/BleachdleWeb") { // Ensure this is the correct directory
        //                 // Create a new buildx builder (with multi-platform support)
        //                 sh '''
        //                     echo "Setting up Docker Buildx builder named Bleachbuild"
        //                     docker buildx create --use --name Bleachbuild
        //                 '''

        //                 // Enable experimental features and build using docker-compose with multi-platform support
        //                 sh '''
        //                     echo "Building the Docker image using Buildx with docker-compose.yml"
        //                     docker buildx build --platform linux/amd64,linux/arm64 -t $IMAGE_NAME:latest -t $IMAGE_NAME:1.0.${VERSION} . --push
        //                 '''
        //             }
        //         }
        //     }
        // }

        stage('Terraform') {
            steps {
                withCredentials([file(credentialsId: 'BLEACH_GCP_CREDENTIALS', variable: 'GCP_CREDENTIALS_FILE')]) {
                    script {
                        dir("${WORKSPACE}/BleachdleWeb/terraform") {
                                sh '''
                                    echo "Using GCP credentials from $GCP_CREDENTIALS_FILE"
                                    export GOOGLE_APPLICATION_CREDENTIALS=$GCP_CREDENTIALS_FILE
                                    
                                    terraform init
                                    terraform plan -out=tfplan
                                    terraform apply -auto-approve tfplan
                                '''
                            }
                        }
                    }
                }
            }
        }


    post {
        always {
            script {
                // Clean up the Buildx builder after the build is complete
                sh '''
                    echo "Cleaning up the Docker Buildx builder"
                '''
            }
        }
    }
}  // <-- This is the final closing brace for the pipeline
