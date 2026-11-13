FROM node:24-slim
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY src/ src/

# Commit id, shown by /health
ARG COMMIT
RUN echo "$COMMIT" > src/commit.txt

ENV PORT=8080
EXPOSE 8080
RUN chown node:node /app
USER node
CMD ["npm", "start"]
