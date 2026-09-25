pipeline {
    agent any

    options {
        // We perform checkout ourselves in the first stage.
        skipDefaultCheckout(true)

        // Prevent two deployments from running at the same time.
        disableConcurrentBuilds()

        // Add timestamps to Jenkins console output.
        timestamps()
    }

    environment {
        DOCKER_REPO   = 'soundar1993/kanban-dashboard'
        CONTAINER_NAME = 'kanban-app'
        APP_PORT       = '3000'
    }

    stages {

        // =====================================================
        // 1. CHECKOUT SOURCE
        // =====================================================
        stage('Checkout Source') {
            steps {
                checkout scm

                script {
                    def shortSha = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    // Dynamic environment variables.
                    // DO NOT put these in the environment {} block.
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${shortSha}"
                    env.PREVIOUS_IMAGE = ''
                    env.DEPLOY_STARTED = 'false'

                    echo """
                    ========================================
                    SOURCE INFORMATION
                    ========================================
                    Build Number : ${env.BUILD_NUMBER}
                    Git SHA      : ${shortSha}
                    Image Tag    : ${env.IMAGE_TAG}
                    ========================================
                    """
                }
            }
        }


        // =====================================================
        // 2. BUILD DOCKER IMAGE
        // =====================================================
        stage('Docker Build') {
            steps {
                sh '''
                    echo "========================================"
                    echo "BUILDING DOCKER IMAGE"
                    echo "========================================"

                    echo "Image:"
                    echo "${DOCKER_REPO}:${IMAGE_TAG}"

                    docker build \
                      -t ${DOCKER_REPO}:${IMAGE_TAG} \
                      .
                '''
            }
        }


        // =====================================================
        // 3. DOCKER SECURITY VALIDATION
        // =====================================================
        stage('Docker Security Validation') {
            steps {
                sh '''
                    echo "========================================"
                    echo "DOCKER SECURITY VALIDATION"
                    echo "========================================"

                    RUNTIME_USER=$(docker image inspect \
                      --format='{{.Config.User}}' \
                      ${DOCKER_REPO}:${IMAGE_TAG})

                    echo "Runtime user: $RUNTIME_USER"

                    if [ "$RUNTIME_USER" != "appuser" ]; then
                        echo "ERROR: Container is not configured with appuser."
                        exit 1
                    fi


                    EXPOSED_PORTS=$(docker image inspect \
                      --format='{{json .Config.ExposedPorts}}' \
                      ${DOCKER_REPO}:${IMAGE_TAG})

                    echo "Exposed ports: $EXPOSED_PORTS"

                    if [ "$EXPOSED_PORTS" != '{"3000/tcp":{}}' ]; then
                        echo "ERROR: Docker image should expose only port 3000."
                        exit 1
                    fi

                    echo "Docker security validation passed."
                '''
            }
        }


        // =====================================================
        // 4. LOGIN AND PUSH TO DOCKER HUB
        // =====================================================
        stage('Push to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_TOKEN'
                    )
                ]) {

                    sh '''
                        echo "========================================"
                        echo "DOCKER HUB PUSH"
                        echo "========================================"

                        echo "$DOCKER_TOKEN" | \
                        docker login \
                          -u "$DOCKER_USER" \
                          --password-stdin

                        docker push \
                          ${DOCKER_REPO}:${IMAGE_TAG}

                        docker logout || true

                        echo "Docker image pushed successfully."
                    '''
                }
            }
        }


        // =====================================================
        // 5. SAVE CURRENT PRODUCTION IMAGE
        // =====================================================
        stage('Save Current Deployment') {
            steps {
                script {

                    env.PREVIOUS_IMAGE = sh(
                        script: '''
                            docker inspect \
                              --format='{{.Config.Image}}' \
                              ${CONTAINER_NAME} \
                              2>/dev/null || true
                        ''',
                        returnStdout: true
                    ).trim()

                    if (env.PREVIOUS_IMAGE) {

                        echo """
                        ========================================
                        CURRENT PRODUCTION VERSION
                        ========================================
                        ${env.PREVIOUS_IMAGE}
                        ========================================
                        """

                    } else {

                        echo """
                        ========================================
                        No previous production deployment found.
                        ========================================
                        """
                    }
                }
            }
        }


        // =====================================================
        // 6. DEPLOY NEW VERSION
        // =====================================================
        stage('Deploy New Version') {
            steps {

                script {
                    env.DEPLOY_STARTED = 'true'
                }

                sh '''
                    echo "========================================"
                    echo "DEPLOYING NEW VERSION"
                    echo "========================================"

                    echo "New image:"
                    echo "${DOCKER_REPO}:${IMAGE_TAG}"


                    echo "Pulling image..."

                    docker pull \
                      ${DOCKER_REPO}:${IMAGE_TAG}


                    echo "Removing existing container..."

                    docker rm -f \
                      ${CONTAINER_NAME} || true


                    echo "Starting new container..."

                    docker run -d \
                      --name ${CONTAINER_NAME} \
                      --restart unless-stopped \
                      --memory=128m \
                      --cpus=0.50 \
                      -p ${APP_PORT}:3000 \
                      ${DOCKER_REPO}:${IMAGE_TAG}
                '''
            }
        }


        // =====================================================
        // 7. DOCKER HEALTH CHECK
        // =====================================================
        stage('Docker Health Check') {
            steps {

                sh '''
                    echo "========================================"
                    echo "WAITING FOR DOCKER HEALTHCHECK"
                    echo "========================================"

                    for i in $(seq 1 18)
                    do

                        HEALTH=$(docker inspect \
                          --format='{{.State.Health.Status}}' \
                          ${CONTAINER_NAME} \
                          2>/dev/null || echo "missing")

                        echo "Attempt $i - Health: $HEALTH"


                        if [ "$HEALTH" = "healthy" ]; then

                            echo "Container is healthy."
                            exit 0

                        fi


                        if [ "$HEALTH" = "unhealthy" ]; then

                            echo "ERROR: Container became unhealthy."

                            echo "Container logs:"

                            docker logs \
                              ${CONTAINER_NAME} \
                              --tail 100 || true

                            exit 1

                        fi


                        sleep 10

                    done


                    echo "ERROR: Docker health check timed out."

                    docker logs \
                      ${CONTAINER_NAME} \
                      --tail 100 || true

                    exit 1
                '''
            }
        }


        // =====================================================
        // 8. HTTP APPLICATION VALIDATION
        // =====================================================
        stage('HTTP Validation') {
            steps {

                sh '''
                    echo "========================================"
                    echo "HTTP APPLICATION VALIDATION"
                    echo "========================================"


                    echo "Testing /health endpoint..."

                    HEALTH_RESPONSE=$(curl -fsS \
                      http://127.0.0.1:${APP_PORT}/health)


                    echo "Health response:"
                    echo "$HEALTH_RESPONSE"


                    if [ "$HEALTH_RESPONSE" != "healthy" ]; then

                        echo "ERROR: Invalid health response."
                        exit 1

                    fi


                    echo "Testing application root endpoint..."

                    curl -fsS \
                      http://127.0.0.1:${APP_PORT}/ \
                      > /dev/null


                    echo "HTTP application validation passed."
                '''
            }
        }


        // =====================================================
        // 9. FINAL DEPLOYMENT INFORMATION
        // =====================================================
        stage('Deployment Information') {
            steps {

                sh '''
                    echo "========================================"
                    echo "DEPLOYMENT INFORMATION"
                    echo "========================================"


                    echo ""
                    echo "Running Container:"
                    docker ps \
                      --filter name=${CONTAINER_NAME}


                    echo ""
                    echo "Running Image:"

                    docker inspect \
                      --format='{{.Config.Image}}' \
                      ${CONTAINER_NAME}


                    echo ""
                    echo "Health Status:"

                    docker inspect \
                      --format='{{.State.Health.Status}}' \
                      ${CONTAINER_NAME}


                    echo ""
                    echo "Runtime User:"

                    docker inspect \
                      --format='{{.Config.User}}' \
                      ${CONTAINER_NAME}


                    echo ""
                    echo "Resource Limits:"

                    docker inspect \
                      --format='Memory={{.HostConfig.Memory}} NanoCPUs={{.HostConfig.NanoCpus}}' \
                      ${CONTAINER_NAME}


                    echo ""
                    echo "========================================"
                '''
            }
        }
    }


    // =========================================================
    // POST ACTIONS
    // =========================================================
    post {

        // -----------------------------------------------------
        // SUCCESS
        // -----------------------------------------------------
        success {

            echo """
            ========================================
            CI/CD DEPLOYMENT SUCCESSFUL
            ========================================

            Docker Image:
            ${env.DOCKER_REPO}:${env.IMAGE_TAG}

            Application Port:
            ${env.APP_PORT}

            ========================================
            """
        }


        // -----------------------------------------------------
        // FAILURE + AUTOMATIC ROLLBACK
        // -----------------------------------------------------
        failure {

            script {

                echo """
                ========================================
                PIPELINE FAILED
                ========================================
                """


                if (
                    env.DEPLOY_STARTED == 'true' &&
                    env.PREVIOUS_IMAGE?.trim()
                ) {

                    echo """
                    ========================================
                    STARTING AUTOMATIC ROLLBACK
                    ========================================

                    Previous image:

                    ${env.PREVIOUS_IMAGE}

                    ========================================
                    """


                    sh '''
                        echo "Showing failed container logs..."

                        docker logs \
                          ${CONTAINER_NAME} \
                          --tail 100 || true


                        echo "Removing failed container..."

                        docker rm -f \
                          ${CONTAINER_NAME} || true


                        echo "Ensuring previous image exists..."

                        docker pull \
                          "${PREVIOUS_IMAGE}" || true


                        echo "Starting previous production image..."

                        docker run -d \
                          --name ${CONTAINER_NAME} \
                          --restart unless-stopped \
                          --memory=128m \
                          --cpus=0.50 \
                          -p ${APP_PORT}:3000 \
                          "${PREVIOUS_IMAGE}"


                        echo "Waiting for rollback health check..."


                        for i in $(seq 1 18)
                        do

                            HEALTH=$(docker inspect \
                              --format='{{.State.Health.Status}}' \
                              ${CONTAINER_NAME} \
                              2>/dev/null || echo "missing")


                            echo "Rollback attempt $i - Health: $HEALTH"


                            if [ "$HEALTH" = "healthy" ]; then

                                echo "Rollback container is healthy."

                                curl -fsS \
                                  http://127.0.0.1:${APP_PORT}/health \
                                  || true

                                exit 0

                            fi


                            if [ "$HEALTH" = "unhealthy" ]; then

                                echo "Rollback container is unhealthy."

                                docker logs \
                                  ${CONTAINER_NAME} \
                                  --tail 100 || true

                                exit 1

                            fi


                            sleep 10

                        done


                        echo "Rollback health check timed out."

                        docker logs \
                          ${CONTAINER_NAME} \
                          --tail 100 || true
                    '''

                } else {

                    echo """
                    ========================================
                    AUTOMATIC ROLLBACK NOT REQUIRED
                    ========================================

                    Possible reasons:

                    - Failure occurred before deployment
                    - No previous production image exists

                    ========================================
                    """
                }
            }
        }


        // -----------------------------------------------------
        // ALWAYS
        // -----------------------------------------------------
        always {

            sh '''
                echo "========================================"
                echo "FINAL DOCKER CONTAINER STATUS"
                echo "========================================"

                docker ps -a || true

                echo ""

                echo "========================================"
                echo "FINAL DISK USAGE"
                echo "========================================"

                docker system df || true
            '''
        }
    }
}