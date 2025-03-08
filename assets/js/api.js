'use strict';

// API Service Module
WatsonX.api = {
    // Generic API request method with proper error handling
    async request(endpoint, method = 'GET', data = null) {
        try {
            // Show loading indicator for longer operations
            if (method !== 'GET') {
                WatsonX.ui.toggleLoading(true);
            }

            const options = {
                method,
                headers: {
                    'Content-Type': 'application/json'
                }
            };

            if (data) {
                options.body = JSON.stringify(data);
            }

            const response = await fetch(`${WatsonX.state.apiBaseUrl}/${endpoint}`, options);

            if (!response.ok) {
                throw new Error(`API error: ${response.status} ${response.statusText}`);
            }

            return await response.json();
        } catch (error) {
            WatsonX.ui.showError(`API request failed: ${error.message}`);
            throw error;
        } finally {
            if (method !== 'GET') {
                WatsonX.ui.toggleLoading(false);
            }
        }
    },

    // Get system status information
    async getSystemStatus() {
        try {
            return await this.request('system/status');
        } catch (error) {
            console.error('Failed to get system status:', error);
            return null;
        }
    },

    // Start code review for a file or project
    async startCodeReview(filePath, options) {
        return await this.request('code/review', 'POST', { file_path: filePath, options });
    },

    // Get available models
    async getAvailableModels() {
        try {
            return await this.request('models/available');
        } catch (error) {
            console.error('Failed to get available models:', error);
            return [];
        }
    },

    // Install a new model
    async installModel(modelId, options) {
        return await this.request('models/install', 'POST', { model_id: modelId, options });
    },

    // Get AI assistance for a prompt
    async getAIAssistance(prompt) {
        return await this.request('assistant/generate', 'POST', { prompt });
    }
};
