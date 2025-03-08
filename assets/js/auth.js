'use strict';

// Authentication and Authorization Module
WatsonX.auth = {
    // Auth state
    isAuthenticated: false,
    currentUser: null,
    token: null,
    roles: [],
    permissions: [],
    
    // Initialize authentication
    init() {
        // Check for existing session
        this.checkExistingSession();
        
        // Set up event listeners
        this.setupEventListeners();
        
        // Set up password toggle functionality
        this.setupPasswordToggle();
    },
    
    // Check for existing session
    checkExistingSession() {
        try {
            // Check for token in localStorage
            const token = localStorage.getItem('watsonx-auth-token');
            const userData = localStorage.getItem('watsonx-user-data');
            
            if (token && userData) {
                // Validate token
                this.validateToken(token)
                    .then(isValid => {
                        if (isValid) {
                            // Parse user data
                            this.currentUser = JSON.parse(userData);
                            this.token = token;
                            this.isAuthenticated = true;
                            
                            // Parse roles and permissions
                            this.roles = this.currentUser.roles || [];
                            this.permissions = this.currentUser.permissions || [];
                            
                            // Update UI
                            this.updateUIForAuthenticatedUser();
                            
                            // Hide auth overlay
                            WatsonX.ui.toggleAuthOverlay(false);
                            
                            console.log('User authenticated from existing session');
                        } else {
                            // Token invalid, show login screen
                            this.logout(false);
                        }
                    })
                    .catch(error => {
                        console.error('Error validating token:', error);
                        this.logout(false);
                    });
            } else {
                // No existing session, show auth overlay
                WatsonX.ui.toggleAuthOverlay(true);
            }
        } catch (error) {
            console.error('Error checking existing session:', error);
            WatsonX.ui.toggleAuthOverlay(true);
        }
    },
    
    // Set up event listeners for auth-related elements
    setupEventListeners() {
        // Login form submission
        const loginForm = document.getElementById('loginForm');
        if (loginForm) {
            loginForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.handleLogin();
            });
        }
        
        // Guest login
        const guestLoginBtn = document.getElementById('guestLoginBtn');
        if (guestLoginBtn) {
            guestLoginBtn.addEventListener('click', () => {
                this.handleGuestLogin();
            });
        }
        
        // Logout
        const logoutBtn = document.getElementById('logoutBtn');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.logout();
            });
        }
    },
    
    // Set up password visibility toggle
    setupPasswordToggle() {
        const toggleBtn = document.querySelector('.password-toggle');
        if (!toggleBtn) return;
        
        toggleBtn.addEventListener('click', () => {
            const pwdInput = document.getElementById('password');
            const icon = toggleBtn.querySelector('i');
            
            if (pwdInput.type === 'password') {
                pwdInput.type = 'text';
                icon.classList.remove('bi-eye');
                icon.classList.add('bi-eye-slash');
            } else {
                pwdInput.type = 'password';
                icon.classList.remove('bi-eye-slash');
                icon.classList.add('bi-eye');
            }
        });
    },
    
    // Handle login form submission
    async handleLogin() {
        try {
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            const rememberMe = document.getElementById('rememberMe').checked;
            
            if (!username || !password) {
                WatsonX.ui.showError('Please enter both username and password');
                return;
            }
            
            // Show loading indicator
            WatsonX.ui.toggleLoading(true);
            
            // Authenticate user
            const authResult = await this.authenticateUser(username, password);
            
            // Process authentication result
            if (authResult.success) {
                // Set user data
                this.currentUser = authResult.userData;
                this.token = authResult.token;
                this.isAuthenticated = true;
                this.roles = authResult.userData.roles || [];
                this.permissions = authResult.userData.permissions || [];
                
                // Store session if remember me is checked
                if (rememberMe) {
                    localStorage.setItem('watsonx-auth-token', this.token);
                    localStorage.setItem('watsonx-user-data', JSON.stringify(this.currentUser));
                } else {
                    // Use session storage for session-only storage
                    sessionStorage.setItem('watsonx-auth-token', this.token);
                    sessionStorage.setItem('watsonx-user-data', JSON.stringify(this.currentUser));
                }
                
                // Update UI
                this.updateUIForAuthenticatedUser();
                
                // Hide auth overlay
                WatsonX.ui.toggleAuthOverlay(false);
                
                // Show welcome message
                WatsonX.ui.showSuccess(`Welcome, ${this.currentUser.displayName || this.currentUser.username}`);
                
                // Log the login event
                WatsonX.telemetry.logEvent('user_login', {
                    user_id: this.currentUser.id,
                    username: this.currentUser.username,
                    method: 'password'
                });
            } else {
                WatsonX.ui.showError(authResult.message || 'Authentication failed');
                
                // Log failed attempt
                WatsonX.telemetry.logEvent('login_failed', {
                    username: username,
                    reason: authResult.message || 'Unknown error'
                });
            }
        } catch (error) {
            console.error('Login error:', error);
            WatsonX.ui.showError('An error occurred during login');
            
            // Log error event
            WatsonX.telemetry.logEvent('login_error', {
                error_message: error.message
            });
        } finally {
            WatsonX.ui.toggleLoading(false);
        }
    },
    
    // Handle guest login
    async handleGuestLogin() {
        try {
            WatsonX.ui.toggleLoading(true);
            
            // Set up guest user
            this.currentUser = {
                id: 'guest-' + Date.now(),
                username: 'guest',
                displayName: 'Guest User',
                roles: ['guest'],
                permissions: ['read:models', 'use:models']
            };
            this.isAuthenticated = true;
            this.token = null;
            this.roles = ['guest'];
            this.permissions = ['read:models', 'use:models'];
            
            // Update UI
            this.updateUIForAuthenticatedUser();
            
            // Hide auth overlay
            WatsonX.ui.toggleAuthOverlay(false);
            
            // Show welcome message
            WatsonX.ui.showSuccess('Welcome, Guest User (Limited access)');
            
            // Log the guest login event
            WatsonX.telemetry.logEvent('guest_login', {
                user_id: this.currentUser.id
            });
        } catch (error) {
            console.error('Guest login error:', error);
            WatsonX.ui.showError('An error occurred during guest login');
        } finally {
            WatsonX.ui.toggleLoading(false);
        }
    },
    
    // Logout user
    logout(showMessage = true) {
        // Clear auth data
        this.isAuthenticated = false;
        this.currentUser = null;
        this.token = null;
        this.roles = [];
        this.permissions = [];
        
        // Clear stored session data
        localStorage.removeItem('watsonx-auth-token');
        localStorage.removeItem('watsonx-user-data');
        sessionStorage.removeItem('watsonx-auth-token');
        sessionStorage.removeItem('watsonx-user-data');
        
        // Show auth overlay
        WatsonX.ui.toggleAuthOverlay(true);
        
        // Show logout message
        if (showMessage) {
            WatsonX.ui.showSuccess('You have been logged out');
        }
        
        // Log logout event
        WatsonX.telemetry.logEvent('user_logout');
        
        // Reset form
        const loginForm = document.getElementById('loginForm');
        if (loginForm) {
            loginForm.reset();
        }
    },
    
    // Update UI for authenticated user
    updateUIForAuthenticatedUser() {
        // Update username display
        const usernameElement = document.getElementById('currentUsername');
        if (usernameElement && this.currentUser) {
            usernameElement.textContent = this.currentUser.displayName || this.currentUser.username;
        }
        
        // Apply role-based UI visibility
        this.applyRoleBasedUIRestrictions();
    },
    
    // Apply role-based restrictions to UI elements
    applyRoleBasedUIRestrictions() {
        // Hide/show elements based on permissions
        document.querySelectorAll('[data-requires-permission]').forEach(el => {
            const requiredPermission = el.dataset.requiresPermission;
            if (this.hasPermission(requiredPermission)) {
                el.classList.remove('d-none');
            } else {
                el.classList.add('d-none');
            }
        });
        
        // Handle admin-only features
        const isAdmin = this.hasRole('admin');
        document.querySelectorAll('[data-admin-only]').forEach(el => {
            if (isAdmin) {
                el.classList.remove('d-none');
                el.removeAttribute('disabled');
            } else {
                el.classList.add('d-none');
                el.setAttribute('disabled', 'disabled');
            }
        });
        
        // Handle guest restrictions
        const isGuest = this.hasRole('guest');
        if (isGuest) {
            document.querySelectorAll('[data-no-guest]').forEach(el => {
                el.classList.add('d-none');
                el.setAttribute('disabled', 'disabled');
            });
        }
    },
    
    // Check if user has a specific permission
    hasPermission(permission) {
        if (!this.isAuthenticated || !this.permissions) return false;
        return this.permissions.includes(permission) || this.permissions.includes('admin:all');
    },
    
    // Check if user has a specific role
    hasRole(role) {
        if (!this.isAuthenticated || !this.roles) return false;
        return this.roles.includes(role);
    },
    
    // Authenticate user (API call)
    async authenticateUser(username, password) {
        // In a real application, this would call your authentication API
        // For demo purposes, we'll simulate a successful authentication
        
        // Simulate API delay
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // For demo: accept any username/password except empty
        if (username && password) {
            return {
                success: true,
                token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6InVzZXItMTIzIiwidXNlcm5hbWUiOiJkZW1vdXNlciIsInJvbGVzIjpbInVzZXIiXSwiaWF0IjoxNTE2MjM5MDIyfQ.4XSbZW_tRzfmQnIj-fvIwwWImBBJ1h4cgCslr-i2nZU',
                userData: {
                    id: 'user-123',
                    username: username,
                    displayName: username.charAt(0).toUpperCase() + username.slice(1),
                    email: `${username}@example.com`,
                    roles: ['user'],
                    permissions: ['read:models', 'use:models', 'create:prompts', 'manage:own-prompts']
                }
            };
        } else {
            return {
                success: false,
                message: 'Invalid username or password'
            };
        }
    },
    
    // Validate token with server
    async validateToken(token) {
        // In a real application, this would validate the token with your server
        // For demo purposes, we'll simulate a valid token
        
        // Simulate API delay
        await new Promise(resolve => setTimeout(resolve, 500));
        
        // Simple validation - check if token looks like JWT
        const tokenParts = token.split('.');
        return tokenParts.length === 3;
    },
    
    // Get auth headers for API requests
    getAuthHeaders() {
        if (!this.isAuthenticated || !this.token) {
            return {};
        }
        
        return {
            'Authorization': `Bearer ${this.token}`
        };
    }
};

// Initialize auth system when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Initialize after main system
    if (WatsonX.initialized) {
        WatsonX.auth.init();
    } else {
        document.addEventListener('watsonx:initialized', () => {
            WatsonX.auth.init();
        });
    }
});
