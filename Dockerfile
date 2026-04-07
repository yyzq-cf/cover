# --- 阶段 1: 安装依赖 ---
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --no-frozen-lockfile

# --- 阶段 2: 编译构建 ---
FROM node:20-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# 使用占位符进行构建，确保这些值被硬编码进 JS 文件
ENV NEXT_PUBLIC_API_ACCESS_KEY=APP_ACCESS_KEY_PLACEHOLDER
ENV NEXT_PUBLIC_API_ICONIFY_URL=APP_ICONIFY_URL_PLACEHOLDER

RUN pnpm run build

# --- 阶段 3: 运行阶段 ---
FROM node:20-alpine AS runner
WORKDIR /app

# 安装 sed 以支持运行时替换
RUN apk add --no-cache sed

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# 创建非 root 用户
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# 【核心优化】只从 standalone 目录拷贝必需文件
# standalone 已经包含了最小化的 node_modules
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 创建启动脚本：支持运行时替换变量
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo 'echo "Replacing placeholders with runtime env..." && \' >> /app/entrypoint.sh && \
    echo 'find .next -type f -name "*.js" -exec sed -i "s|APP_ACCESS_KEY_PLACEHOLDER|${NEXT_PUBLIC_API_ACCESS_KEY}|g" {} +' >> /app/entrypoint.sh && \
    echo 'find .next -type f -name "*.js" -exec sed -i "s|APP_ICONIFY_URL_PLACEHOLDER|${NEXT_PUBLIC_API_ICONIFY_URL}|g" {} +' >> /app/entrypoint.sh && \
    echo 'exec node server.js' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

USER nextjs

EXPOSE 3000

# 运行脚本
ENTRYPOINT ["/app/entrypoint.sh"]
