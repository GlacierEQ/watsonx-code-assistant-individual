'use strict';

// UI Management Module
WatsonX.ui = {
    // DOM References - improves performance by caching DOM lookups
    elements: {},

    // Initialize UI components
    init() {
        // Cache DOM elements
        this.cacheElements();

        // Set up event handlers
        this.setupEventListeners();

        // Set initial UI state
        this.updateTheme();
        this.updateSystemStats();
    },

    // Cache DOM references for better performance
    cacheElements() {
        this.elements = {
            body: document.body,
            themeSwitch: document.getElementById('themeSwitch'),
            loadingOverlay: document.getElementById('loadingOverlay'),
            toastContainer: document.getElementById('toastContainer'),
            userInput: document.getElementById('userInput'),
            chatMessages: document.getElementById('chatMessages'),
            sendMessageBtn: document.getElementById('sendMessageBtn'),
            clearChatBtn: document.getElementById('clearChatBtn'),
            tabButtons: {
                dashboard: document.getElementById('dashboard-tab'),
                codeReview: document.getElementById('codereview-tab'),
                promptEngine: document.getElementById('promptengine-tab'),
                advanced: document.getElementById('advanced-tab')
            }
        };
    },

    // Set up UI event listeners
    setupEventListeners() {
        // Theme switcher
        this.elements.themeSwitch.addEventListener('click', () => this.toggleTheme());
        this.elements.themeSwitch.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                this.toggleTheme();
            }
        });

        // Chat functionality
        if (this.elements.sendMessageBtn) {
            this.elements.sendMessageBtn.addEventListener('click', () => this.sendChatMessage());
        }

        if (this.elements.userInput) {
            this.elements.userInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    this.sendChatMessage();
                }
            });
        }

        if (this.elements.clearChatBtn) {
            this.elements.clearChatBtn.addEventListener('click', () => this.clearChat());
        }

        // Model card selection
        document.querySelectorAll('.model-card').forEach(card => {
            card.addEventListener('click', function () {
                document.querySelectorAll('.model-card').forEach(c => c.classList.remove('active'));
                this.classList.add('active');
            });
        });
    },

    // Toggle theme between light and dark
    toggleTheme() {
        WatsonX.state.isDarkMode = !WatsonX.state.isDarkMode;
        this.updateTheme();
        localStorage.setItem('watsonx-theme', WatsonX.state.isDarkMode ? 'dark' : 'light');
    },

    // Update UI theme based on state
    updateTheme() {
        this.elements.body.classList.toggle('dark-mode', WatsonX.state.isDarkMode);
        this.elements.themeSwitch.setAttribute('aria-checked', WatsonX.state.isDarkMode.toString());

        // Update chart theming if available
        if (WatsonX.charts && WatsonX.charts.updateTheme) {
            WatsonX.charts.updateTheme();
        }
    },

    // Toggle loading overlay
    toggleLoading(isLoading) {
        WatsonX.state.isLoading = isLoading;

        if (this.elements.loadingOverlay) {
            this.elements.loadingOverlay.classList.toggle('visible', isLoading);
        }

        // Disable interactive elements during loading
        const interactiveElements = document.querySelectorAll('button, input, select, a');

        if (isLoading) {
            interactiveElements.forEach(el => {
                if (!el.hasAttribute('data-original-disabled')) {
                    el.setAttribute('data-original-disabled', el.disabled ? 'true' : 'false');
                    el.disabled = true;
                }
            });
        } else {
            interactiveElements.forEach(el => {
                if (el.hasAttribute('data-original-disabled')) {
                    el.disabled = el.getAttribute('data-original-disabled') === 'true';
                    el.removeAttribute('data-original-disabled');
                }
            });
        }
    },

    // Show error notification
    showError(message, type = 'error') {
        console.error(`Error: ${message}`);

        if (!this.elements.toastContainer) return;

        // Create toast notification
        const toastId = 'toast-' + Date.now();
        const toastHTML = `
            <div class="toast" role="alert" aria-live="assertive" aria-atomic="true" id="${toastId}">
                <div class="toast-header ${type === 'error' ? 'bg-danger text-white' : 'bg-warning'}">
                    <strong class="me-auto">${type === 'error' ? 'Error' : 'Warning'}</strong>
                    <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
                </div>
                <div class="toast-body">${message}</div>
            </div>
        `;

        this.elements.toastContainer.insertAdjacentHTML('beforeend', toastHTML);
        const toastElement = document.getElementById(toastId);
        const toast = new bootstrap.Toast(toastElement);
        toast.show();

        // Auto-remove after shown
        toastElement.addEventListener('hidden.bs.toast', () => {
            toastElement.remove();
        });
    },

    // Send a chat message
    sendChatMessage() {
        if (!this.elements.userInput || !this.elements.chatMessages) return;

        const message = this.elements.userInput.value.trim();
        if (!message) return;

        // Add user message to chat
        this.addChatMessage(message, 'user');
        this.elements.userInput.value = '';

        // Get AI response
        this.toggleLoading(true);
        setTimeout(() => {
            const response = this.getAIResponse(message);
            this.addChatMessage(response, 'ai');
            this.toggleLoading(false);
        }, 800);
    },

    // Add a message to the chat window
    addChatMessage(message, sender) {
        if (!this.elements.chatMessages) return;

        const messageClass = sender === 'user' ? 'user-message' : 'ai-message';
        const sanitizedMessage = this.sanitizeHTML(message);

        this.elements.chatMessages.insertAdjacentHTML('beforeend',
            `<div class="message ${messageClass}">${sanitizedMessage}</div>`
        );

        // Scroll to the bottom
        this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
    },

    // Clear the chat
    clearChat() {
        if (this.elements.chatMessages) {
            this.elements.chatMessages.innerHTML = '<div class="message ai-message">Chat cleared. How can I help you?</div>';
        }
    },

    // Get AI response to user input (placeholder for actual API call)
    getAIResponse(message) {
        message = message.toLowerCase();

        // Simple pattern matching for demo purposes
        if (message.includes('gpu') || message.includes('performance')) {
            return "Your GPU performance is optimized. The CUDA acceleration is working properly with TensorRT enabled. Model inference is currently using about 25% of available GPU resources.";
        } else if (message.includes('model') || message.includes('granite')) {
            return "You're currently using the granite-code:8b model. This is optimized for code generation tasks. If you need better performance, consider installing the smaller granite-code:3b model, or for higher quality, the granite-code:13b model.";
        } else if (message.includes('python') || message.includes('code')) {
            return "I can help with Python coding. For example, I can analyze your code for quality issues, suggest improvements, or help you implement new features. Would you like me to check your current project?";
        } else if (message.includes('hello') || message.includes('hi')) {
            return "Hello! I'm your AI assistant for watsonx Code Assistant. I can help you manage your models, optimize performance, or assist with coding tasks.";
        } else if (message.includes('train') || message.includes('learning')) {
            return "The system is currently adapting to your codebase patterns. This helps improve code suggestions. You can configure additional training in the AI Model Training section.";
        } else {
            return "I'm here to help with your watsonx Code Assistant. I can provide information about models, performance optimization, or help with coding tasks. What would you like to know?";
        }
    },

    // Update system statistics in the UI
    updateSystemStats() {
        const stats = WatsonX.state.systemResources;

        // Update GPU card
        const gpuCard = document.querySelector('.card:nth-child(3)');
        if (gpuCard) {
            const progressBar = gpuCard.querySelector('.progress-bar');
            const usageText = gpuCard.querySelector('.text-muted.mt-2.mb-0');

            if (progressBar) {
                progressBar.style.width = `${stats.gpu.usage}%`;
                progressBar.textContent = `${stats.gpu.usage}%`;
                progressBar.setAttribute('aria-valuenow', stats.gpu.usage);
            }

            if (usageText) {
                usageText.textContent = `${stats.gpu.memory.used}GB / ${stats.gpu.memory.total}GB VRAM`;
            }
        }

        // More UI updates for CPU, RAM, etc.
    },

    // HTML sanitizer to prevent XSS
    sanitizeHTML(str) {
        const temp = document.createElement('div');
        temp.textContent = str;
        return temp.innerHTML;
    }
};
