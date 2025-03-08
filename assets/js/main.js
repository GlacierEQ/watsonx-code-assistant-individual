'use strict';

// Application namespace
const WatsonX = {};

// Application state management
WatsonX.state = {
    isDarkMode: false,
    isLoading: false,
    activeModel: 'granite-code:8b',
    systemResources: {
        gpu: { usage: 25, memory: { used: 1.2, total: 8 } },
        cpu: { usage: 15 },
        ram: { used: 2.4, total: 16 }
    },
    apiBaseUrl: 'http://localhost:5000/api'
};

// Initialize the application
WatsonX.init = function () {
    // Load saved preferences
    this.loadPreferences();

    // Initialize UI components
    this.ui.init();

    // Initialize charts
    this.charts.init();

    // Initialize voice commands if supported
    this.voice.init();

    // Initialize code review functionality
    this.codeReview.init();

    // Initialize prompt engineering functionality
    this.promptEngine.init();

    // Start system monitoring
    this.startSystemMonitoring();

    console.log('WatsonX Code Assistant Dashboard initialized');
};

// Load user preferences from localStorage
WatsonX.loadPreferences = function () {
    try {
        // Load theme preference
        const savedTheme = localStorage.getItem('watsonx-theme');
        if (savedTheme === 'dark') {
            this.state.isDarkMode = true;
            document.body.classList.add('dark-mode');
        }

        // Load other preferences as needed
    } catch (error) {
        console.error('Error loading preferences:', error);
    }
};

// Start system resource monitoring
WatsonX.startSystemMonitoring = async function () {
    try {
        // Initial update
        await this.updateSystemStatus();

        // Set interval for periodic updates
        setInterval(async () => {
            await this.updateSystemStatus();
        }, 5000);
    } catch (error) {
        console.error('Failed to start system monitoring:', error);
        this.ui.showError('System monitoring could not be initialized');
    }
};

// Update system status from API
WatsonX.updateSystemStatus = async function () {
    try {
        const systemStatus = await this.api.getSystemStatus();
        if (!systemStatus) return;

        // Update state with real data
        this.state.systemResources = {
            gpu: {
                usage: systemStatus.gpu?.memory_allocated ?
                    Math.round((systemStatus.gpu.memory_allocated / systemStatus.gpu.memory_total) * 100) : 25,
                memory: {
                    used: systemStatus.gpu?.memory_allocated ?
                        (systemStatus.gpu.memory_allocated / 1e9).toFixed(1) : 1.2,
                    total: systemStatus.gpu?.memory_total ?
                        (systemStatus.gpu.memory_total / 1e9).toFixed(1) : 8
                }
            },
            cpu: {
                usage: systemStatus.cpu?.percent || 15
            },
            ram: {
                used: systemStatus.memory?.available ?
                    ((systemStatus.memory.total - systemStatus.memory.available) / 1e9).toFixed(1) : 2.4,
                total: systemStatus.memory?.total ?
                    (systemStatus.memory.total / 1e9).toFixed(1) : 16
            }
        };

        // Update UI with new system data
        this.ui.updateSystemStats();

    } catch (error) {
        console.error('Error updating system status:', error);
    }
};

// Initialize application when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    WatsonX.init();
});
