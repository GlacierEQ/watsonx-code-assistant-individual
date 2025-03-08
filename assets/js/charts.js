'use strict';

// Charts Management Module
WatsonX.charts = {
    // Chart instances
    instances: {},

    // Initialize charts
    init() {
        try {
            // Initialize GPU usage chart
            this.initGpuChart();

            // Start the update cycle
            this.startChartUpdates();
        } catch (error) {
            console.error('Failed to initialize charts:', error);
            WatsonX.ui.showError('Chart initialization failed');
        }
    },

    // Initialize GPU usage chart
    initGpuChart() {
        const ctx = document.getElementById('gpuChart');
        if (!ctx) return;

        this.instances.gpuChart = new Chart(ctx.getContext('2d'), {
            type: 'line',
            data: {
                labels: Array.from({ length: 10 }, (_, i) => `${i}m ago`).reverse(),
                datasets: [{
                    label: 'GPU Utilization',
                    data: [5, 8, 15, 20, 25, 30, 25, 20, 15, 25],
                    borderColor: '#0f62fe',
                    backgroundColor: 'rgba(15, 98, 254, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        title: {
                            display: true,
                            text: 'Percentage'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false,
                        labels: {
                            color: WatsonX.state.isDarkMode ? '#fff' : '#666'
                        }
                    },
                    tooltip: {
                        mode: 'index',
                        intersect: false,
                        callbacks: {
                            label: function (context) {
                                return `GPU: ${context.raw}%`;
                            }
                        }
                    }
                }
            }
        });
    },

    // Start periodic chart updates
    startChartUpdates() {
        setInterval(() => {
            this.updateCharts();
        }, 2000);
    },

    // Update all charts with latest data
    updateCharts() {
        this.updateGpuChart();
    },

    // Update GPU chart with latest data
    updateGpuChart() {
        const chart = this.instances.gpuChart;
        if (!chart) return;

        // Get real GPU usage from state
        const gpuUsage = WatsonX.state.systemResources.gpu.usage;

        // Update chart data
        chart.data.datasets[0].data.shift();
        chart.data.datasets[0].data.push(gpuUsage);
        chart.update('none'); // Use 'none' for better performance
    },

    // Update chart themes when dark mode changes
    updateTheme() {
        for (const chartName in this.instances) {
            const chart = this.instances[chartName];
            if (chart && chart.options && chart.options.plugins && chart.options.plugins.legend) {
                chart.options.plugins.legend.labels.color = WatsonX.state.isDarkMode ? '#fff' : '#666';
                chart.update('none');
            }
        }
    }
};
