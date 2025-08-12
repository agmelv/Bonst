# ---- Base ----
# Use a specific version of Node.js for reproducibility.
# 'alpine' is a lightweight Linux distribution.
FROM node:22-alpine AS base
WORKDIR /build

# ---- Builder ----
# This stage installs dependencies and builds the application.
FROM base AS builder

# Copy LICENSE file.
COPY LICENSE ./

# Copy package.json and lock files for all workspaces.
# This is done first to leverage Docker's layer caching.
# If these files don't change, Docker won't re-run 'npm install'.
COPY package*.json ./
COPY packages/server/package*.json ./packages/server/
COPY packages/core/package*.json ./packages/core/
COPY packages/frontend/package*.json ./packages/frontend/

# Install all dependencies for all workspaces.
RUN npm install

# Copy the rest of your source code.
COPY tsconfig.*json ./
COPY packages/server ./packages/server
COPY packages/core ./packages/core
COPY packages/frontend ./packages/frontend
COPY scripts ./scripts
COPY resources ./resources

# Build the entire project.
RUN npm run build

# Remove development-only dependencies to reduce the final image size.
RUN npm --workspaces prune --omit=dev


# ---- Final Image ----
# This stage creates the final, lean image that will be deployed.
FROM base AS final

# Create a non-root user 'node' and a group 'node'.
# Running as a non-root user is a critical security best practice.
RUN addgroup -S node && adduser -S node -G node

# Set the working directory in the final image.
WORKDIR /app

# Explicitly install 'wget' for the HEALTHCHECK command.
RUN apk add --no-cache wget

# Copy necessary files from the 'builder' stage, and set ownership to the 'node' user.
# The --chown flag ensures our non-root user can read/write these files.
COPY --from=builder --chown=node:node /build/package*.json /build/LICENSE ./
COPY --from=builder --chown=node:node /build/packages/core/package.*json ./packages/core/
COPY --from=builder --chown=node:node /build/packages/frontend/package.*json ./packages/frontend/
COPY --from=builder --chown=node:node /build/packages/server/package.*json ./packages/server/

# Copy the built application code.
COPY --from=builder --chown=node:node /build/packages/core/dist ./packages/core/dist
COPY --from=builder --chown=node:node /build/packages/frontend/out ./packages/frontend/out
COPY --from=builder --chown=node:node /build/packages/server/dist ./packages/server/dist

# Copy any other required assets.
COPY --from=builder --chown=node:node /build/resources ./resources
COPY --from=builder --chown=node:node /build/node_modules ./node_modules

# Switch to the non-root user.
USER node

# Healthcheck to ensure the application is running correctly.
# Fly.io uses this to determine if a deployment is successful.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-3000}/api/v1/status || exit 1

# Expose the port the app will run on. Fly.io provides the PORT env var.
EXPOSE ${PORT:-3000}

# The command to start the application.
ENTRYPOINT ["npm", "run", "start"]
