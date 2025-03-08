'use strict';

// Voice Commands Module
WatsonX.voice = {
    // State
    recognition: null,
    isRecording: false,

    // Initialize voice recognition
    init() {
        try {
            // Check browser support
            if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
                console.warn('Web Speech API not supported in this browser');
                const voiceBtn = document.getElementById('voiceCommandBtn');
                if (voiceBtn) voiceBtn.style.display = 'none';
                return;
            }

            // Initialize recognition
            this.recognition = new (window.SpeechRecognition || window.webkitSpeechRecognition)();
            this.configureRecognition();

            // Set up voice button
            this.setupVoiceButton();
        } catch (error) {
            console.error('Failed to initialize voice commands:', error);
            WatsonX.ui.showError('Voice command initialization failed');
        }
    },

    // Configure recognition settings
    configureRecognition() {
        if (!this.recognition) return;

        this.recognition.continuous = false;
        this.recognition.interimResults = false;
        this.recognition.lang = 'en-US';

        // Set up event handlers
        this.recognition.onstart = this.handleRecognitionStart.bind(this);
        this.recognition.onend = this.handleRecognitionEnd.bind(this);
        this.recognition.onerror = this.handleRecognitionError.bind(this);
        this.recognition.onresult = this.handleRecognitionResult.bind(this);
    },

    // Recognition event handlers
    handleRecognitionStart() {
        console.log('Voice recognition started');
        this.isRecording = true;

        const voiceBtn = document.getElementById('voiceCommandBtn');
        if (voiceBtn) {
            voiceBtn.classList.add('recording');
            voiceBtn.setAttribute('aria-label', 'Stop voice command (recording)');
        }
    },

    handleRecognitionEnd() {
        console.log('Voice recognition ended');
        this.isRecording = false;

        const voiceBtn = document.getElementById('voiceCommandBtn');
        if (voiceBtn) {
            voiceBtn.classList.remove('recording');
            voiceBtn.setAttribute('aria-label', 'Start voice command');
        }
    },

    handleRecognitionError(event) {
        console.error('Voice recognition error:', event.error);
        this.isRecording = false;

        const voiceBtn = document.getElementById('voiceCommandBtn');
        if (voiceBtn) {
            voiceBtn.classList.remove('recording');
        }

        WatsonX.ui.showError(`Voice recognition error: ${event.error}`, 'warning');
    },

    handleRecognitionResult(event) {
        try {
            const transcript = event.results[0][0].transcript.toLowerCase();
            console.log('Voice command recognized:', transcript);
            this.processCommand(transcript);
        } catch (error) {
            console.error('Error processing voice result:', error);
            WatsonX.ui.showError('Failed to process voice command');
        }
    },

    // Set up voice button
    setupVoiceButton() {
        const voiceBtn = document.getElementById('voiceCommandBtn');
        if (!voiceBtn) return;

        voiceBtn.addEventListener('click', this.toggleRecognition.bind(this));
    },

    // Toggle voice recognition
    toggleRecognition() {
        if (this.isRecording) {
            this.stopListening();
        } else {
            this.startListening();
        }
    },

    // Start voice recognition
    startListening() {
        try {
            if (!this.recognition) return;
            this.recognition.start();
        } catch (error) {
            console.error('Failed to start voice recognition:', error);
            WatsonX.ui.showError('Failed to start voice recognition');
        }
    },

    // Stop voice recognition
    stopListening() {
        try {
            if (!this.recognition) return;
            this.recognition.stop();
        } catch (error) {
            console.error('Failed to stop voice recognition:', error);
        }
    },

    // Process recognized command
    processCommand(command) {
        // Log the command in chat
        WatsonX.ui.addChatMessage(`Voice command: ${command}`, 'user');

        // Define command patterns
        const commandPatterns = [
            {
                pattern: /model|status|dashboard/i,
                action: () => this.switchTab('dashboard'),
                response: 'Showing dashboard with model status'
            },
            {
                pattern: /code\s+review|analyze\s+code/i,
                action: () => this.switchTab('codereview'),
                response: 'Opening code review tool'
            },
            {
                pattern: /prompt|engineering/i,
                action: () => this.switchTab('promptengine'),
                response: 'Opening prompt engineering interface'
            },
            {
                pattern: /optimize|performance/i,
                action: () => {
                    WatsonX.ui.addChatMessage('Analyzing code for optimization opportunities...', 'ai');
                    setTimeout(() => {
                        this.switchTab('codereview');
                        WatsonX.ui.addChatMessage('Found 3 performance improvement opportunities. See Code Review tab.', 'ai');
                    }, 1500);
                    return false; // Don't send default response
                }
            },
            {
                pattern: /help|command/i,
                action: () => {
                    WatsonX.ui.addChatMessage(`
                        <strong>Available voice commands:</strong><br>
                        - "Show model status" - View dashboard<br>
                        - "Start code review" - Open code analysis<br>
                        - "Open prompt engineering" - Design custom prompts<br>
                        - "Optimize my code" - Find performance improvements<br>
                        - "Help" - Show this message
                    `, 'ai');
                    return false; // Don't send default response
                }
            }
        ];

        // Find matching command
        for (const cmdPattern of commandPatterns) {
            if (cmdPattern.pattern.test(command)) {
                const shouldRespond = cmdPattern.action() !== false;
                if (shouldRespond && cmdPattern.response) {
                    WatsonX.ui.addChatMessage(cmdPattern.response, 'ai');
                }
                return;
            }
        }

        // No command matched, treat as a normal chat message
        setTimeout(() => {
            const response = WatsonX.ui.getAIResponse(command);
            WatsonX.ui.addChatMessage(response, 'ai');
        }, 500);
    },

    // Switch to specified tab
    switchTab(tabId) {
        const tabButton = document.getElementById(`${tabId}-tab`);
        if (tabButton) {
            tabButton.click();
            return true;
        }
        return false;
    }
};
