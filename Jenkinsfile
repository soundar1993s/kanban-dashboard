pipeline {
    agent any

    environment {
        DOCKER_REPO = 'soundar1993/kanban-dashboard'
        CONTAINER_NAME = 'kanban-app'
        APP_PORT = '3000'

        IMAGE_TAG = ''
        PREVIOUS_IMAGE = ''
        DEPLOY_STARTED = 'false'
    }

    stages {

        stage('Checkout Source') {
            steps {
                checkout scm

                script {
                        def shortSha = sh(
                            script: 'git rev-parse --short HEAD',
                            returnStdout: true
                        ).trim()

                        env.IMAGE_TAG = "${env.BUILD_NUMBER}-${shortSha}"

                        echo "Build Number : ${env.BUILD_NUMBER}"
                        echo "Git SHA      : ${shortSha}"
                        echo "Image Tag    : ${env.IMAGE_TAG}"
                    }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                      -t ${DOCKER_REPO}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Docker Security Validation') {
            steps {
                sh '''
                    echo "Runtime user:"
                    docker image inspect \
                      --format='{{.Config.User}}' \
                      ${DOCKER_REPO}:${IMAGE_TAG}

                    echo "Exposed ports:"
                    docker image inspect \
                      --format='{{json .Config.ExposedPorts}}' \
                      ${DOCKER_REPO}:${IMAGE_TAG}
                '''
            }
        }

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
                        echo "$DOCKER_TOKEN" | \
                        docker login \
                          -u "$DOCKER_USER" \
                          --password-stdin

                        docker push \
                          ${DOCKER_REPO}:${IMAGE_TAG}

                        docker logout
                    '''
                }
            }
        }

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
                        echo "Current production image: ${env.PREVIOUS_IMAGE}"
                    } else {
                        echo "No previous deployment found."
                    }
                }
            }
        }

        stage('Deploy New Version') {
            steps {
                script {
                    env.DEPLOY_STARTED = 'true'
                }

                sh '''
                    echo "Deploying ${DOCKER_REPO}:${IMAGE_TAG}"

                    docker pull \
                      ${DOCKER_REPO}:${IMAGE_TAG}

                    docker rm -f \
                      ${CONTAINER_NAME} || true

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

        stage('Docker Health Check') {
            steps {
                sh '''
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
                            echo "Container is unhealthy."

                            docker logs \
                              ${CONTAINER_NAME} \
                              --tail 100 || true

                            exit 1
                        fi

                        sleep 10
                    done

                    echo "Health check timed out."

                    docker logs \
                      ${CONTAINER_NAME} \
                      --tail 100 || true

                    exit 1
                '''
            }
        }

        stage('HTTP Validation') {
            steps {
                sh '''
                    HEALTH_RESPONSE=$(curl -fsS \
                      http://127.0.0.1:${APP_PORT}/health)

                    echo "Health response: $HEALTH_RESPONSE"

                    test "$HEALTH_RESPONSE" = "healthy"

                    curl -fsS \
                      http://127.0.0.1:${APP_PORT}/ \
                      > /dev/null

                    echo "HTTP validation passed."
                '''
            }
        }

        stage('Deployment Information') {
            steps {
                sh '''
                    echo "Running image:"

                    docker inspect \
                      --format='{{.Config.Image}}' \
                      ${CONTAINER_NAME}

                    echo "Health status:"

                    docker inspect \
                      --format='{{.State.Health.Status}}' \
                      ${CONTAINER_NAME}

                    echo "Runtime user:"

                    docker inspect \
                      --format='{{.Config.User}}' \
                      ${CONTAINER_NAME}
                '''
            }
        }
    }

    post {

        success {
                echo """
                ========================================
                DEPLOYMENT SUCCESSFUL

                Image:
                ${env.DOCKER_REPO}:${env.IMAGE_TAG}
                ========================================
                """
            }

        failure {
            script {

                if (
                    env.DEPLOY_STARTED == 'true' &&
                    env.PREVIOUS_IMAGE?.trim()
                ) {

                    echo """
                    ========================================
                    DEPLOYMENT FAILED
                    ROLLING BACK TO:

                    ${env.PREVIOUS_IMAGE}
                    ========================================
                    """

                    sh '''
                        echo "Failed deployment logs:"

                        docker logs \
                          ${CONTAINER_NAME} \
                          --tail 100 || true

                        docker rm -f \
                          ${CONTAINER_NAME} || true

                        docker pull \
                          "${PREVIOUS_IMAGE}" || true

                        docker run -d \
                          --name ${CONTAINER_NAME} \
                          --restart unless-stopped \
                          --memory=128m \
                          --cpus=0.50 \
                          -p ${APP_PORT}:3000 \
                          "${PREVIOUS_IMAGE}"

                        sleep 35

                        echo "Rollback container:"

                        docker ps \
                          --filter name=${CONTAINER_NAME}

                        echo "Rollback health:"

                        docker inspect \
                          --format='{{.State.Health.Status}}' \
                          ${CONTAINER_NAME} || true
                    '''
                } else {
                    echo "No rollback required or no previous image available."
                }
            }
        }

        always {
            sh '''
                echo "Docker containers:"
                docker ps -a || true
            '''
        }
    }
}