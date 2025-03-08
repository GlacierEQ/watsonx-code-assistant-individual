'use strict';

// Prompt Engineering Module
WatsonX.promptEngine = {
    // Module state
    activePromptModules: [],
    
    // Initialize prompt engineering functionality
    init() {
        this.setupDragAndDrop();
        this.setupPromptTemplates();
        this.setupCreativitySlider();
        this.setupPromptButtons();
    },
    
    // Set up drag and drop for prompt modules
    setupDragAndDrop() {
        // Make modules draggable
        document.querySelectorAll('.prompt-module').forEach(module => {
            module.setAttribute('draggable', true);
            
            module.addEventListener('dragstart', this.handleDragStart.bind(this));
            module.addEventListener('dragend', this.handleDragEnd.bind(this));
        });
        
        // Set up drop zone
        const dropZone = document.getElementById('promptDropZone');
        if (dropZone) {
            dropZone.addEventListener('dragover', this.handleDragOver.bind(this));
            dropZone.addEventListener('dragleave', this.handleDragLeave.bind(this));
            dropZone.addEventListener('drop', this.handleDrop.bind(this));
        }
    },
    
    // Drag event handlers
    handleDragStart(event) {
        const module = event.currentTarget;
        event.dataTransfer.setData('text/plain', module.innerHTML);
        module.classList.add('dragging');
    },
    
    handleDragEnd(event) {
        event.currentTarget.classList.remove('dragging');
    },
    
    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('border-primary');
    },
    
    handleDragLeave(event) {
        event.currentTarget.classList.remove('border-primary');
    },
    
    handleDrop(event) {
        event.preventDefault();
        const dropZone = event.currentTarget;
        dropZone.classList.remove('border-primary');
        
        try {
            const moduleHTML = event.dataTransfer.getData('text/plain');
            if (!moduleHTML) return;
            
            // Remove placeholder if present
            const placeholder = dropZone.querySelector('.text-center.text-muted');
            if (placeholder) {
                dropZone.innerHTML = '';
            }
            
            // Create module element
            const moduleElement = document.createElement('div');
            moduleElement.className = 'prompt-module';
            moduleElement.innerHTML = moduleHTML;
            
            // Extract module type for tracking
            const moduleType = moduleElement.querySelector('.prompt-module-header')?.textContent;
            if (moduleType) {
                this.activePromptModules.push(moduleType);
            }
            
            // Add remove button
            const removeBtn = document.createElement('button');
            removeBtn.className = 'btn btn-sm btn-outline-danger float-end';
            removeBtn.innerHTML = '<i class="bi bi-x"></i>';
            removeBtn.setAttribute('aria-label', 'Remove module');
            
            // Set up remove functionality
            removeBtn.addEventListener('click', () => {
                moduleElement.remove();
                
                // Remove from active modules
                if (moduleType) {
                    const index = this.activePromptModules.indexOf(moduleType);
                    if (index !== -1) {
                        this.activePromptModules.splice(index, 1);
                    }
                }
                
                // Restore placeholder if empty
                if (dropZone.children.length === 0) {
                    this.resetDropZone(dropZone);
                }
            });
            
            moduleElement.prepend(removeBtn);
            dropZone.appendChild(moduleElement);
        } catch (error) {
            console.error('Error handling drop:', error);
            WatsonX.ui.showError('Failed to add prompt module');
        }
    },
    
    // Reset drop zone to empty state
    resetDropZone(dropZone) {
        dropZone.innerHTML = `
            <div class="text-center text-muted p-5">
                <i class="bi bi-arrows-move fs-1"></i>
                <p>Drag modules here to build your prompt</p>
            </div>
        `;
        this.activePromptModules = [];
    },
    
    // Set up prompt template selection
    setupPromptTemplates() {
        document.querySelectorAll('.prompt-template').forEach(template => {
            template.addEventListener('click', this.loadPromptTemplate.bind(this));
        });
    },
    
    // Load a predefined prompt template
    loadPromptTemplate(event) {
        const template = event.currentTarget;
        const templateName = template.querySelector('strong')?.textContent;
        
        if (!templateName) return;
        
        try {
            const dropZone = document.getElementById('promptDropZone');
            if (!dropZone) return;
            
            // Clear current modules
            this.resetDropZone(dropZone);
            
            // Get custom prompt textarea
            const customText = document.getElementById('customPromptText');
            
            // Set content based on template
            switch (templateName) {
                case 'Bug Fixer Pro':
                    this.loadBugFixerTemplate(dropZone, customText);
                    break;
                case 'Code Architect':
                    this.loadArchitectTemplate(dropZone, customText);
                    break;
                case 'Optimization Expert':
                    this.loadOptimizationTemplate(dropZone, customText);
                    break;
                default:
                    WatsonX.ui.showError('Unknown template');
            }
            
            // Update creativity slider based on template type
            this.updateCreativityForTemplate(templateName);
        } catch (error) {
            console.error('Error loading template:', error);
            WatsonX.ui.showError('Failed to load prompt template');
        }
    },
    
    // Update creativity slider based on template
    updateCreativityForTemplate(templateName) {
        const creativitySlider = document.getElementById('creativitySlider');
        if (!creativitySlider) return;
        
        switch (templateName) {
            case 'Bug Fixer Pro':
                creativitySlider.value = 2; // More precise
                break;
            case 'Code Architect':
                creativitySlider.value = 7; // More creative
                break;
            case 'Optimization Expert':
                creativitySlider.value = 4; // Somewhat precise
                break;
        }
        
        // Trigger the input event to update the label
        creativitySlider.dispatchEvent(new Event('input'));
    },
    
    // Template-specific loaders
    loadBugFixerTemplate(dropZone, customText) {
        // Clear placeholder
        dropZone.innerHTML = '';
        
        // Add debugging module
        this.addModuleToDropZone(dropZone, 'Debugging', 'Find and fix errors in code');
        this.activePromptModules.push('Debugging');
        
        // Set custom text
        if (customText) {
            customText.value = 'Find bugs in the provided code and suggest fixes. Explain why the bug occurs and how your solution resolves it. Focus on correctness rather than style improvements.';
        }
    },
    
    loadArchitectTemplate(dropZone, customText) {
        // Clear placeholder
        dropZone.innerHTML = '';
        
        // Add modules
        this.addModuleToDropZone(dropZone, 'Code Generation', 'Optimize for generating high-quality code');
        this.addModuleToDropZone(dropZone, 'Refactoring', 'Improve code structure and design');
        this.activePromptModules.push('Code Generation', 'Refactoring');
        
        // Set custom text
        if (customText) {
            customText.value = 'Design a robust architecture for the described system. Consider scalability, maintainability, and performance. Provide clear component diagrams and explain interactions.';
        }
    },
    
    loadOptimizationTemplate(dropZone, customText) {
        // Clear placeholder
        dropZone.innerHTML = '';
        
        // Add debugging module
        this.addModuleToDropZone(dropZone, 'Refactoring', 'Improve code structure and design');
        this.activePromptModules.push('Refactoring');
        
        // Set custom text
        if (customText) {
            customText.value = 'Analyze the provided code for performance bottlenecks. Suggest optimizations that improve execution speed and memory usage. Provide before/after performance estimates.';
        }
    },
    
    // Add a module to the drop zone
    addModuleToDropZone(dropZone, title, description) {
        const moduleElement = document.createElement('div');
        moduleElement.className = 'prompt-module';
        
        // Create module content
        moduleElement.innerHTML = `
            <div class="prompt-module-header">${title}</div>
            <small>${description}</small>
        `;
        
        // Add remove button
        const removeBtn = document.createElement('button');
        removeBtn.className = 'btn btn-sm btn-outline-danger float-end';
        removeBtn.innerHTML = '<i class="bi bi-x"></i>';
        removeBtn.setAttribute('aria-label', 'Remove module');
        
        // Set up remove functionality
        removeBtn.addEventListener('click', () => {
            moduleElement.remove();
            
            // Remove from active modules
            const index = this.activePromptModules.indexOf(title);
            if (index !== -1) {
                this.activePromptModules.splice(index, 1);
            }
            
            // Restore placeholder if empty
            if (dropZone.children.length === 0) {
                this.resetDropZone(dropZone);
            }
        });
        
        moduleElement.prepend(removeBtn);
        dropZone.appendChild(moduleElement);
    },
    
    // Set up creativity slider
    setupCreativitySlider() {
        const slider = document.getElementById('creativitySlider');
        const valueDisplay = document.getElementById('creativityValue');
        
        if (slider && valueDisplay) {
            slider.addEventListener('input', () => {
                const value = slider.value;
                valueDisplay.textContent = this.getCreativityLabelForValue(value);
            });
        }
    },
    
    // Get creativity label based on slider value
    getCreativityLabelForValue(value) {
        if (value <= 2) return "Very Precise";
        if (value <= 4) return "Precise";
        if (value <= 6) return "Balanced";
        if (value <= 8) return "Creative";
        return "Very Creative";
    },
    
    // Set up prompt action buttons
    setupPromptButtons() {
        const saveBtn = document.getElementById('savePromptBtn');
        if (saveBtn) {
            saveBtn.addEventListener('click', this.savePrompt.bind(this));
        }
        
        const executeBtn = document.getElementById('executePromptBtn');
        if (executeBtn) {
            executeBtn.addEventListener('click', this.executePrompt.bind(this));
        }
    },
    
    // Save current prompt configuration
    savePrompt() {
        try {
            // Get custom text and creativity value
            const customText = document.getElementById('customPromptText')?.value || '';
            const creativity = document.getElementById('creativitySlider')?.value || 5;
            
            // Build prompt data
            const promptData = {
                modules: this.activePromptModules,
                customText,
                creativity,
                timestamp: new Date().toISOString(),
                name: `Prompt ${new Date().toLocaleString()}`
            };
            
            // Save to local storage
            const savedPrompts = JSON.parse(localStorage.getItem('watsonx-saved-prompts') || '[]');
            savedPrompts.push(promptData);
            localStorage.setItem('watsonx-saved-prompts', JSON.stringify(savedPrompts));
            
            // Show success message
            WatsonX.ui.showError('Prompt saved successfully', 'success');
        } catch (error) {
            console.error('Error saving prompt:', error);
            WatsonX.ui.showError('Failed to save prompt');
        }
    },
    
    // Execute the current prompt
    executePrompt() {
        try {
            // Build the prompt
            const customText = document.getElementById('customPromptText')?.value || '';
            const creativity = document.getElementById('creativitySlider')?.value || 5;
            
            if (this.activePromptModules.length === 0 && !customText.trim()) {
                WatsonX.ui.showError('Please add modules or custom instructions to your prompt');
                return;
            }
            
            // Show loading state
            WatsonX.ui.toggleLoading(true);
            
            // Build the final prompt
            const prompt = this.buildExecutablePrompt(customText, creativity);
            
            // Call API to process prompt
            setTimeout(() => {
                // In a real implementation, we'd call an API here
                console.log('Executing prompt:', prompt);
                
                // Show results in the chat window
                const chatMessages = document.getElementById('chatMessages');
                if (chatMessages) {
                    // Add the prompt to chat
                    const userMessage = `<strong>Custom Prompt:</strong> ${WatsonX.ui.sanitizeHTML(customText)}`;
                    WatsonX.ui.addChatMessage(userMessage, 'user');
                    
                    // Add sample response - in real app this would come from the API
                    setTimeout(() => {
                        const response = "I've analyzed your prompt and generated a solution. Here's a code architecture that addresses your requirements: [generated code would appear here]";
                        WatsonX.ui.addChatMessage(response, 'ai');
                        
                        // Switch to the dashboard tab to show the chat
                        document.getElementById('dashboard-tab')?.click();
                        
                        // Hide loading state
                        WatsonX.ui.toggleLoading(false);
                    }, 1500);
                } else {
                    WatsonX.ui.toggleLoading(false);
                    WatsonX.ui.showError('Chat window not found');
                }
            }, 1000);
        } catch (error) {
            console.error('Error executing prompt:', error);
            WatsonX.ui.showError('Failed to execute prompt');
            WatsonX.ui.toggleLoading(false);
        }
    },
    
    // Build the final executable prompt
    buildExecutablePrompt(customText, creativity) {
        let promptParts = [];
        
        // Add system instructions based on modules
        if (this.activePromptModules.includes('Code Generation')) {
            promptParts.push("Focus on generating high-quality, efficient code.");
        }
        
        if (this.activePromptModules.includes('Code Explanation')) {
            promptParts.push("Analyze the provided code and provide clear explanations.");
        }
        
        if (this.activePromptModules.includes('Refactoring')) {
            promptParts.push("Improve code structure, readability, and maintainability while preserving functionality.");
        }
        
        if (this.activePromptModules.includes('Debugging')) {
            promptParts.push("Identify and fix bugs or potential issues in the code.");
        }
        
        if (this.activePromptModules.includes('Testing')) {
            promptParts.push("Generate comprehensive test cases or testing code.");
        }
        
        // Add creativity instructions
        if (creativity <= 2) {
            promptParts.push("Prioritize precision and correctness over creativity. Use established patterns and approaches.");
        } else if (creativity >= 8) {
            promptParts.push("Be highly creative and innovative in your approach. Explore multiple solutions.");
        }
        
        // Add custom text
        if (customText.trim()) {
            promptParts.push(customText.trim());
        }
        
        // Combine all parts
        return promptParts.join("\n\n");
    }
};
