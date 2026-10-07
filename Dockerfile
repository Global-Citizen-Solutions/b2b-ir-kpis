# Serves the one static file this repo publishes (the dashboard) on Azure
# Container Apps. .github/workflows/dashboard-data.yml builds it fresh after
# every data refresh, bakes it into this image and hands the image to
# gcs-azure-infrastructure's reusable deploy-container-app.yml workflow.
#
# The page is PLAINTEXT (no password lock any more): access is controlled by
# Entra ID sign-in in front of the app, and the file is never committed, it
# only exists in the CI workspace and in this image.
#
# nginx-unprivileged runs as a non-root user and listens on 8080, which the
# workflow passes as target_port.
FROM nginxinc/nginx-unprivileged:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY outputs/index.html /usr/share/nginx/html/index.html

EXPOSE 8080
