#!/bin/bash

# 构建 workspace
cd workspace
npm install
npm run build
npm run dist:all:parallel