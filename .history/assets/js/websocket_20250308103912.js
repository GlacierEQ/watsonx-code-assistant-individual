'use strict';

// WebSocket Realtime Communication Module
WatsonX.websocket = {
    // Connection state
    socket: null,
    isConnected: false,
    reconnectAttempts: 0,
    maxReconnectAttempts: 5,
    reconnectInterval: 3000,
    messageHandlers: {},
    pendingMessages: [],
    collaborators: [],
    
    // Initialize WebSocket connection
    init() {
        try {
            // Create WebSocket URL based on current location
            const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
            const wsBase = protocol + window.location.host + '/ws';
            
            // Connect with session ID if available
            const sessionId = localStorage.getItem('watsonx-session-id') || '';
            const wsUrl = `${wsBase}?session=${encodeURIComponent(sessionId)}`;
            
            // Initialize connection
            this.connect(wsUrl);
            
            // Register message handlers
            this.registerHandlers();
            
            console.log('WebSocket module initialized');
        } catch (error) {
            console.error('Failed to initialize WebSocket:', error);
            WatsonX.ui.showError('Failed to initialize real-time communication');
        }
    },
    
    // Connect to WebSocket server
    connect(url) {
        try {
            this.socket = new WebSocket(url);
            
            // Set up event handlers
            this.socket.onopen = this.handleOpen.bind(this);
            this.socket.onclose = this.handleClose.bind(this);
            this.socket.onerror = this.handleError.bind(this);
            this.socket.onmessage = this.handleMessage.bind(this);
        } catch (error) {
            console.error('WebSocket connection error:', error);
            this.scheduleReconnect();
        }
    },
    
    // Handle WebSocket open event
    handleOpen(event) {
        console.log('WebSocket connection established');
        this.isConnected = true;
        this.reconnectAttempts = 0;
        
        // Update UI to show connected state
        WatsonX.ui.updateConnectionStatus(true);
        
        // Send any pending messages
        this.sendPendingMessages();
        
        // Announce presence to get collaborator list
        this.sendMessage('system.announce', {
            clientName: WatsonX.state.userName || 'Anonymous User',
            clientId: WatsonX.state.clientId
        });
    },
    
    // Handle WebSocket close event
    handleClose(event) {
        this.isConnected = false;
        WatsonX.ui.updateConnectionStatus(false);
        
        console.log(`WebSocket connection closed (Code: ${event.code})`);
        
        // Attempt to reconnect if not a deliberate closure
        if (event.code !== 1000) {
            this.scheduleReconnect();
        }
    },
    
    // Handle WebSocket errors
    handleError(error) {
        console.error('WebSocket error:', error);
        this.isConnected = false;
        WatsonX.ui.updateConnectionStatus(false);
    },
    
    // Handle incoming WebSocket messages
    handleMessage(event) {
        try {
            const data = JSON.parse(event.data);
            
            if (!data || !data.type) {
                console.warn('Received invalid WebSocket message format');
                return;
            }
            
            console.log(`Received WebSocket message of type: ${data.type}`);
            
            // Call the appropriate handler based on message type
            if (this.messageHandlers[data.type]) {
                this.messageHandlers[data.type](data.payload);
            } else {
                console.warn(`No handler registered for message type: ${data.type}`);
            }
        } catch (error) {
            console.error('Error processing WebSocket message:', error);
        }
    },
    
    // Schedule reconnection attempt
    scheduleReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.log('Maximum reconnection attempts reached');
            WatsonX.ui.showError('Could not re-establish connection to server. Please refresh the page.');
            return;
        }
        
        this.reconnectAttempts++;
        
        // Exponential backoff
        const delay = this.reconnectInterval * Math.pow(1.5, this.reconnectAttempts - 1);
        console.log(`Scheduling reconnection attempt ${this.reconnectAttempts} in ${delay}ms`);
        
        setTimeout(() => {
            if (!this.isConnected) {
                console.log(`Reconnection attempt ${this.reconnectAttempts}`);
                this.init();
            }
        }, delay);
    },
    
    // Send message via WebSocket
    sendMessage(type, payload = {}) {
        const message = JSON.stringify({
            type,
            payload,
            clientId: WatsonX.state.clientId,
            timestamp: Date.now()
        });
        
        if (this.isConnected && this.socket.readyState === WebSocket.OPEN) {
            this.socket.send(message);
        } else {
            // Store message to send when connection is established
            this.pendingMessages.push(message);
        }
    },
    
    // Send any pending messages
    sendPendingMessages() {
        if (this.pendingMessages.length > 0) {
            console.log(`Sending ${this.pendingMessages.length} pending messages`);
            
            this.pendingMessages.forEach(message => {
                this.socket.send(message);
            });
            
            this.pendingMessages = [];
        }
    },
    
    // Register message handlers
    registerHandlers() {
        this.messageHandlers = {
            // System messages
            'system.welcome': this.handleWelcomeMessage.bind(this),
            'system.error': this.handleErrorMessage.bind(this),
            'system.collaborators': this.handleCollaboratorsMessage.bind(this),
            
            // Resource updates
            'resource.status': this.handleResourceStatusMessage.bind(this),
            'model.update': this.handleModelUpdateMessage.bind(this),
            
            // Collaborative features
            'collaboration.cursor': this.handleCursorUpdateMessage.bind(this),
            'collaboration.edit': this.handleEditMessage.bind(this),
            'collaboration.chat': this.handleChatMessage.bind(this),
            
            // Notifications
            'notification': this.handleNotificationMessage.bind(this)
        };
    },
    
    // Message type handlers
    handleWelcomeMessage(payload) {
        console.log('Connected to server:', payload.serverInfo);
        
        // Save session ID if provided
        if (payload.sessionId) {
            localStorage.setItem('watsonx-session-id', payload.sessionId);
        }
        
        // Update client ID
        if (payload.clientId) {
            WatsonX.state.clientId = payload.clientId;
        }
        
        // Update UI with server info
        WatsonX.ui.updateServerInfo(payload.serverInfo);
    },
    
    handleErrorMessage(payload) {
        console.error('Server error:', payload.message);
        WatsonX.ui.showError(payload.message);
    },
    
    handleCollaboratorsMessage(payload) {
        this.collaborators = payload.collaborators || [];
        console.log(`Collaborators online: ${this.collaborators.length}`);
        
        // Update UI with collaborator information
        WatsonX.ui.updateCollaborators(this.collaborators);
    },
    
    handleResourceStatusMessage(payload) {
        console.log('Resource status update:', payload);
        
        // Update system resource state
        if (payload.system) {
            WatsonX.state.systemResources = {
                ...WatsonX.state.systemResources,
                ...payload.system
            };
        }
        
        // Update UI with new resource data
        WatsonX.ui.updateSystemStats();
        WatsonX.charts.updateCharts();
    },
    
    handleModelUpdateMessage(payload) {
        console.log('Model update:', payload);
        
        // Update active model info
        if (payload.modelInfo) {
            WatsonX.state.activeModel = payload.modelInfo.name;
            
            // Update UI elements
            const activeModelName = document.getElementById('activeModelName');
            if (activeModelName) {
                activeModelName.textContent = payload.modelInfo.name;
            }
            
            const activeModelSize = document.getElementById('activeModelSize');
            if (activeModelSize) {
                activeModelSize.textContent = `${payload.modelInfo.size} loaded`;
            }
        }
        
        // Handle model downloads/updates
        if (payload.action === 'downloading') {
            WatsonX.ui.showModelDownloadProgress(payload.modelInfo.name, payload.progress);
        } else if (payload.action === 'completed') {
            WatsonX.ui.completeModelDownload(payload.modelInfo.name);
        }
    },
    
    handleCursorUpdateMessage(payload) {
        // Handle collaborative cursor updates
        if (payload.userId !== WatsonX.state.clientId) {
            WatsonX.collaboration.updateRemoteCursor(payload);
        }
    },
    
    handleEditMessage(payload) {
        // Handle collaborative edits
        if (payload.userId !== WatsonX.state.clientId) {
            WatsonX.collaboration.applyRemoteEdit(payload);
        }
    },
    
    handleChatMessage(payload) {
        // Add message to chat if from another user
        if (payload.userId !== WatsonX.state.clientId) {
            WatsonX.ui.addCollaborativeChatMessage(payload.message, payload.userName);
        }
    },
    
    handleNotificationMessage(payload) {
        // Display notification to user
        WatsonX.ui.showNotification(payload.title, payload.message, payload.type);
    },
    
    // Send a collaborative chat message
    sendChatMessage(message) {
        this.sendMessage('collaboration.chat', {
            message: message,
            userName: WatsonX.state.userName || 'Anonymous User'
        });
    },
    
    // Broadcast cursor position
    sendCursorPosition(position) {
        this.sendMessage('collaboration.cursor', position);
    },
    
    // Broadcast edit
    sendEdit(edit) {
        this.sendMessage('collaboration.edit', edit);
    },
    
    // Close WebSocket connection
    close() {
        if (this.socket && this.isConnected) {
            this.socket.close(1000, 'User navigated away');
        }
    }
};

// Register for page unload to clean up connection
window.addEventListener('beforeunload', () => {
    WatsonX.websocket.close();
});
