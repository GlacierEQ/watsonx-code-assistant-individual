'use strict';

// Analytics and Telemetry Module
WatsonX.telemetry = {
    // Configuration
    config: {
        enabled: true,
        consentGranted: false,
        anonymizeIPs: true,
        samplingRate: 0.5,  // Log 50% of events
        maxQueueSize: 20,
        flushInterval: 30000 // 30 seconds
    },
    
    // State
    eventQueue: [],
    sessionId: null,
    isFlushPending: false,
    
    // Initialize telemetry system
    init() {
        // Check user consent from storage
        this.loadConsentPreferences();
        
        // Generate session ID
        this.sessionId = this.generateSessionId();
        
        // Set up event listeners
        this.setupEventListeners();
        
        // Set up automatic flush interval
        this.setupAutoFlush();
        
        // Log initialization event
        this.logEvent('system_initialized', {
            userAgent: navigator.userAgent,
            screenSize: `${window.innerWidth}x${window.innerHeight}`,
            timestamp: Date.now()
        });
        
        console.log('Telemetry module initialized');
    },
    
    // Generate a unique session ID
    generateSessionId() {
        const timestamp = Date.now().toString(36);
        const randomStr = Math.random().toString(36).substring(2, 10);
        return `${timestamp}-${randomStr}`;
    },
    
    // Load user consent preferences
    loadConsentPreferences() {
        try {
            const consentPref = localStorage.getItem('watsonx-telemetry-consent');
            this.config.consentGranted = consentPref === 'granted';
            
            // If consent hasn't been decided yet, we'll need to show the consent prompt
            if (consentPref === null) {
                this.scheduleConsentPrompt();
            }
        } catch (error) {
            console.error('Failed to load telemetry consent preferences:', error);
            this.config.consentGranted = false;
        }
    },
    
    // Schedule showing the consent prompt
    scheduleConsentPrompt() {
        // Wait for UI to be ready before showing
        setTimeout(() => {
            this.showConsentPrompt();
        }, 3000);
    },
    
    // Show consent prompt to user
    showConsentPrompt() {
        // Create consent dialog
        const consentHtml = `
            <div class="modal" id="telemetryConsentModal" tabindex="-1" aria-labelledby="telemetryConsentModalLabel" aria-hidden="true">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title" id="telemetryConsentModalLabel">Help Improve Watsonx</h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                        </div>
                        <div class="modal-body">
                            <p>We collect anonymous usage data to improve the application and provide better features. This data includes:</p>
                            <ul>
                                <li>Feature usage statistics</li>
                                <li>Performance metrics</li>
                                <li>Error reports</li>
                            </ul>
                            <p>We <strong>do not</strong> collect:</p>
                            <ul>
                                <li>Your code or project contents</li>
                                <li>Personal information</li>
                                <li>Model outputs or prompts</li>
                            </ul>
                            <p>You can change this setting anytime in your preferences.</p>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-outline-secondary" id="declineTelemetryBtn">Decline</button>
                            <button type="button" class="btn btn-primary" id="acceptTelemetryBtn">Accept</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        // Add to DOM
        document.body.insertAdjacentHTML('beforeend', consentHtml);
        
        // Initialize modal
        const modalElement = document.getElementById('telemetryConsentModal');
        if (!modalElement) return;
        
        const modal = new bootstrap.Modal(modalElement);
        
        // Set up event listeners
        document.getElementById('acceptTelemetryBtn')?.addEventListener('click', () => {
            this.setConsent(true);
            modal.hide();
        });
        
        document.getElementById('declineTelemetryBtn')?.addEventListener('click', () => {
            this.setConsent(false);
            modal.hide();
        });
        
        // Show the modal
        modal.show();
        
        // Add event listener to remove from DOM when hidden
        modalElement.addEventListener('hidden.bs.modal', () => {
            modalElement.remove();
        });
    },
    
    // Set user consent preference
    setConsent(granted) {
        this.config.consentGranted = granted;
        localStorage.setItem('watsonx-telemetry-consent', granted ? 'granted' : 'declined');
        
        // Log consent change event (not subject to consent itself)
        this.logSystemEvent('consent_preference_changed', {
            granted: granted,
            timestamp: Date.now()
        });
        
        // If consent was granted and we have events queued, flush them
        if (granted && this.eventQueue.length > 0) {
            this.flushEvents();
        }
    },
    
    // Set up DOM event listeners for automatic tracking
    setupEventListeners() {
        // Track page navigation
        window.addEventListener('hashchange', this.handleHashChange.bind(this));
        
        // Track feature usage via click events using data attributes
        document.body.addEventListener('click', this.handleFeatureClick.bind(this), true);
        
        // Track errors
        window.addEventListener('error', this.handleError.bind(this));
        window.addEventListener('unhandledrejection', this.handleUnhandledRejection.bind(this));
    },
    
    // Handle hash change for analytics
    handleHashChange(event) {
        const newPath = window.location.hash || '#';
        this.logEvent('navigation', {
            path: newPath
        });
    },
    
    // Track feature usage via clicked elements with data-feature attribute
    handleFeatureClick(event) {
        const target = event.target.closest('[data-feature]');
        if (!target) return;
        
        const feature = target.dataset.feature;
        if (!feature) return;
        
        this.logEvent('feature_used', {
            feature: feature,
            context: target.dataset.featureContext || null
        });
    },
    
    // Handle JavaScript errors
    handleError(event) {
        this.logError('js_error', {
            message: event.message,
            source: event.filename,
            line: event.lineno,
            column: event.colno
        });
    },
    
    // Handle unhandled promise rejections
    handleUnhandledRejection(event) {
        let message = 'Unknown Promise Error';
        if (event.reason && typeof event.reason.message === 'string') {
            message = event.reason.message;
        } else if (typeof event.reason === 'string') {
            message = event.reason;
        }
        
        this.logError('unhandled_promise_rejection', {
            message: message
        });
    },
    
    // Set up automatic flushing of events
    setupAutoFlush() {
        setInterval(() => {
            if (this.eventQueue.length > 0) {
                this.flushEvents();
            }
        }, this.config.flushInterval);
    },
    
    // Log an event (subject to consent)
    logEvent(eventName, eventData = {}) {
        // Skip if telemetry is disabled or we need consent and don't have it
        if (!this.config.enabled || (!this.config.consentGranted && eventName !== 'system_initialized')) {
            return;
        }
        
        // Apply sampling rate - randomly skip some events
        if (Math.random() > this.config.samplingRate) {
            return;
        }
        
        // Create event object
        const event = {
            event: eventName,
            category: this.categorizeEvent(eventName),
            data: eventData,
            timestamp: Date.now(),
            sessionId: this.sessionId,
            clientId: WatsonX.state.clientId || 'anonymous'
        };
        
        // Add to queue
        this.eventQueue.push(event);
        
        // Flush if queue is getting full
        if (this.eventQueue.length >= this.config.maxQueueSize) {
            this.flushEvents();
        }
        
        // Log to console in development
        if (process.env.NODE_ENV === 'development') {
            console.debug('📊 Analytics event:', eventName, eventData);
        }
    },
    
    // Log a system event (not subject to consent)
    logSystemEvent(eventName, eventData = {}) {
        // System events are logged regardless of consent settings
        // but still respect the enabled flag
        if (!this.config.enabled) {
            return;
        }
        
        // Create event object
        const event = {
            event: eventName,
            category: 'system',
            data: eventData,
            timestamp: Date.now(),
            sessionId: this.sessionId,
            clientId: WatsonX.state.clientId || 'anonymous',
            isSystemEvent: true
        };
        
        // Send immediately
        this.sendEvents([event]);
    },
    
    // Log an error event (with special handling)
    logError(errorType, errorData = {}) {
        // Skip if telemetry is disabled or no consent
        if (!this.config.enabled || !this.config.consentGranted) {
            return;
        }
        
        // Create error event with more complete context
        const event = {
            event: errorType,
            category: 'error',
            data: {
                ...errorData,
                url: window.location.href,
                userAgent: navigator.userAgent,
                viewport: `${window.innerWidth}x${window.innerHeight}`
            },
            timestamp: Date.now(),
            sessionId: this.sessionId,
            clientId: WatsonX.state.clientId || 'anonymous'
        };
        
        // Add to queue but prioritize flushing
        this.eventQueue.push(event);
        
        // Attempt to flush immediately for errors
        this.flushEvents(true);
    },
    
    // Categorize events based on name
    categorizeEvent(eventName) {
        if (eventName.startsWith('system_')) return 'system';
        if (eventName.includes('error')) return 'error';
        if (eventName.includes('model_')) return 'model';
        if (eventName.includes('prompt_')) return 'prompt';
        if (eventName.includes('feature_')) return 'feature';
        if (eventName === 'navigation') return 'navigation';
        if (eventName.includes('user_')) return 'user';
        return 'general';
    },
    
    // Flush events to server
    async flushEvents(immediate = false) {
        // Skip if no events or already flushing
        if (this.eventQueue.length === 0 || (this.isFlushPending && !immediate)) {
            return;
        }
        
        // Mark as pending
        this.isFlushPending = true;
        
        // Create a copy and clear the queue
        const events = [...this.eventQueue];
        this.eventQueue = [];
        
        try {
            await this.sendEvents(events);
        } catch (error) {
            console.error('Failed to send analytics events:', error);
            
            // Put events back in queue on failure
            this.eventQueue = [...events, ...this.eventQueue];
            
            // Limit queue size if it gets too large
            if (this.eventQueue.length > this.config.maxQueueSize * 2) {
                this.eventQueue = this.eventQueue.slice(-this.config.maxQueueSize);
            }
        } finally {
            this.isFlushPending = false;
        }
    },
    
    // Send events to analytics endpoint
    async sendEvents(events) {
        // For demo purposes, we'll just log to console
        // In a real app, this would send to your analytics endpoint
        
        if (process.env.NODE_ENV === 'development') {
            console.log('📤 Would send events to analytics server:', events);
            return Promise.resolve({ success: true });
        }
        
        // Dummy implementation - in real app, make API call here
        await new Promise(resolve => setTimeout(resolve, 500));
        return { success: true, count: events.length };
        
        /* Real implementation would be something like:
        return fetch('/api/analytics/events', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                events,
                clientInfo: {
                    userAgent: navigator.userAgent,
                    language: navigator.language,
                    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
                }
            })
        }).then(response => {
            if (!response.ok) {
                throw new Error(`Analytics API returned ${response.status}`);
            }
            return response.json();
        });
        */
    }
};

// Initialize telemetry when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Initialize after main WatsonX object
    if (WatsonX.initialized) {
        WatsonX.telemetry.init();
    } else {
        document.addEventListener('watsonx:initialized', () => {
            WatsonX.telemetry.init();
        });
    }
});
