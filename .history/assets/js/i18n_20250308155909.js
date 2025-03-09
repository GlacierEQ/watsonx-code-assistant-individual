'use strict';

// Internationalization Module
WatsonX.i18n = {
    // Current state
    currentLocale: 'en',
    supportedLocales: ['en', 'es', 'fr', 'de', 'ja', 'zh', 'ko'],
    translations: {},
    isLoaded: false,
    
    // Initialize i18n system
    async init() {
        try {
            // Detect user preference
            this.detectUserLocale();
            
            // Load translations
            await this.loadTranslations(this.currentLocale);
            
            // Apply translations to the page
            this.translatePage();
            
            // Set up language selector if present
            this.setupLanguageSelector();
            
            console.log(`Internationalization initialized with locale: ${this.currentLocale}`);
            this.isLoaded = true;
            
            // Dispatch event for other modules that might depend on translations
            document.dispatchEvent(new CustomEvent('i18n:loaded', { 
                detail: { locale: this.currentLocale } 
            }));
        } catch (error) {
            console.error('Failed to initialize i18n:', error);
            // Fall back to English if there's an error
            if (this.currentLocale !== 'en') {
                this.currentLocale = 'en';
                await this.init();
            }
        }
    },
    
    // Detect user's preferred locale
    detectUserLocale() {
        try {
            // Check for saved preference
            const savedLocale = localStorage.getItem('watsonx-locale');
            if (savedLocale && this.supportedLocales.includes(savedLocale)) {
                this.currentLocale = savedLocale;
                return;
            }
            
            // Check browser language
            const browserLang = navigator.language.split('-')[0];
            if (this.supportedLocales.includes(browserLang)) {
                this.currentLocale = browserLang;
                return;
            }
            
            // Default to English
            this.currentLocale = 'en';
        } catch (error) {
            console.error('Error detecting user locale:', error);
            this.currentLocale = 'en';
        }
    },
    
    // Load translation file for specified locale
    async loadTranslations(locale) {
        try {
            // Normalize locale
            locale = locale || this.currentLocale;
            
            // Fetch translations file
            const response = await fetch(`/locales/${locale}.json`);
            
            if (!response.ok) {
                throw new Error(`Failed to load translations for ${locale}`);
            }
            
            this.translations = await response.json();
        } catch (error) {
            console.error(`Failed to load translations for ${locale}:`, error);
            
            // Fall back to English if the requested locale failed
            if (locale !== 'en') {
                console.log('Falling back to English translations');
                await this.loadTranslations('en');
            } else {
                // Empty translations as last resort
                this.translations = {};
            }
        }
    },
    
    // Translate the entire page
    translatePage() {
        // Get all elements with data-i18n attribute
        const elements = document.querySelectorAll('[data-i18n]');
        
        elements.forEach(el => {
            const key = el.getAttribute('data-i18n');
            const translation = this.translate(key);
            
            if (translation) {
                // Check if element has data-i18n-attr to set a specific attribute
                const attribute = el.getAttribute('data-i18n-attr');
                if (attribute) {
                    el.setAttribute(attribute, translation);
                } else {
                    el.textContent = translation;
                }
            }
        });
        
        // Handle placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            const translation = this.translate(key);
            
            if (translation) {
                el.setAttribute('placeholder', translation);
            }
        });
        
        // Handle tooltips
        document.querySelectorAll('[data-i18n-title]').forEach(el => {
            const key = el.getAttribute('data-i18n-title');
            const translation = this.translate(key);
            
            if (translation) {
                el.setAttribute('title', translation);
            }
        });
    },
    
    // Get a translation value by key
    translate(key) {
        if (!key) return '';
        
        // Handle nested keys (e.g., "auth.signin")
        const parts = key.split('.');
        let value = this.translations;
        
        for (const part of parts) {
            if (!value || typeof value !== 'object') {
                return key; // Return the key if path not found
            }
            value = value[part];
        }
        
        if (typeof value === 'string') {
            return value;
        }
        
        // Return the key if no translation found
        return key;
    },
    
    // Format a string with variables
    formatString(key, variables = {}) {
        let text = this.translate(key);
        
        // Replace {{variableName}} with actual values
        Object.entries(variables).forEach(([name, value]) => {
            text = text.replace(new RegExp(`{{\\s*${name}\\s*}}`, 'g'), value);
        });
        
        return text;
    },
    
    // Setup language selector dropdown
    setupLanguageSelector() {
        const selector = document.getElementById('languageSelector');
        if (!selector) return;
        
        // Clear existing options
        selector.innerHTML = '';
        
        // Add options for supported locales
        this.supportedLocales.forEach(locale => {
            const option = document.createElement('option');
            option.value = locale;
            option.textContent = this.getLanguageDisplayName(locale);
            option.selected = locale === this.currentLocale;
            selector.appendChild(option);
        });
        
        // Add event listener
        selector.addEventListener('change', (e) => {
            this.changeLocale(e.target.value);
        });
    },
    
    // Change current locale
    async changeLocale(locale) {
        if (locale === this.currentLocale) return;
        
        if (this.supportedLocales.includes(locale)) {
            // Save preference
            localStorage.setItem('watsonx-locale', locale);
            
            // Update state
            this.currentLocale = locale;
            
            // Load and apply new translations
            await this.loadTranslations(locale);
            this.translatePage();
            
            // Update language selector if exists
            const selector = document.getElementById('languageSelector');
            if (selector) {
                selector.value = locale;
            }
            
            // Log the locale change for telemetry
            if (WatsonX.telemetry) {
                WatsonX.telemetry.logEvent('locale_changed', { locale });
            }
            
            // Dispatch event for other modules
            document.dispatchEvent(new CustomEvent('i18n:changed', { 
                detail: { locale } 
            }));
        }
    },
    
    // Get display name for a language
    getLanguageDisplayName(locale) {
        const displayNames = {
            'en': 'English',
            'es': 'Español',
            'fr': 'Français',
            'de': 'Deutsch',
            'ja': '日本語',
            'zh': '中文',
            'ko': '한국어'
        };
        
        return displayNames[locale] || locale;
    },
    
    // Add a new translation dynamically
    addTranslation(key, value) {
        // Handle nested keys
        const parts = key.split('.');
        let current = this.translations;
        
        // Navigate to the correct nesting level
        for (let i = 0; i < parts.length - 1; i++) {
            const part = parts[i];
            if (!current[part] || typeof current[part] !== 'object') {
                current[part] = {};
            }
            current = current[part];
        }
        
        // Set the value
        current[parts[parts.length - 1]] = value;
    }
};

// Initialize i18n when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Initialize after main system
    if (WatsonX.initialized) {
        WatsonX.i18n.init();
    } else {
        document.addEventListener('watsonx:initialized', () => {
            WatsonX.i18n.init();
        });
    }
});
