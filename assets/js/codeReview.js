'use strict';

// Code Review Module
WatsonX.codeReview = {
    // Initialize code review functionality
    init() {
        this.setupEventListeners();
    },

    // Set up event listeners
    setupEventListeners() {
        const reviewBtn = document.getElementById('startCodeReviewBtn');
        if (reviewBtn) {
            reviewBtn.addEventListener('click', this.startCodeReview.bind(this));
        }

        // Set up individual review item actions
        document.querySelectorAll('.review-item .btn-outline-primary').forEach(btn => {
            btn.addEventListener('click', this.showFix.bind(this));
        });

        document.querySelectorAll('.review-item .btn-outline-secondary').forEach(btn => {
            btn.addEventListener('click', this.ignoreIssue.bind(this));
        });
    },

    // Start code review process
    async startCodeReview() {
        try {
            const reviewBtn = document.getElementById('startCodeReviewBtn');
            if (!reviewBtn) return;

            // Update button state
            reviewBtn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Analyzing...';
            reviewBtn.disabled = true;

            // Get file path and options
            const filePathInput = document.getElementById('codeReviewPath');
            const filePath = filePathInput ? filePathInput.value || 'current-project' : 'current-project';

            const options = {
                performance: document.getElementById('reviewPerformance')?.checked || false,
                security: document.getElementById('reviewSecurity')?.checked || false,
                style: document.getElementById('reviewStyle')?.checked || false,
                bugs: document.getElementById('reviewBugs')?.checked || false
            };

            // Call API to perform code review
            const result = await WatsonX.api.startCodeReview(filePath, options);

            // Display results
            this.displayReviewResults(result);

            // Reset button state
            reviewBtn.innerHTML = '<i class="bi bi-search"></i> Start New Review';
            reviewBtn.disabled = false;
        } catch (error) {
            console.error('Code review failed:', error);

            // Reset button state
            const reviewBtn = document.getElementById('startCodeReviewBtn');
            if (reviewBtn) {
                reviewBtn.innerHTML = '<i class="bi bi-search"></i> Start New Review';
                reviewBtn.disabled = false;
            }

            WatsonX.ui.showError('Failed to complete code review');
        }
    },

    // Display code review results
    displayReviewResults(results) {
        const resultsContainer = document.getElementById('reviewResults');
        if (!resultsContainer) return;

        // For demo purposes, we're using the existing HTML content
        // In a real application, this would dynamically create the results based on the API response

        // Make sure the results are visible
        resultsContainer.style.display = 'block';
    },

    // Show suggested fix for an issue
    showFix(event) {
        const btn = event.currentTarget;
        const reviewItem = btn.closest('.review-item');
        if (!reviewItem) return;

        // Find code snippet or create one if needed
        let codeSnippet = reviewItem.querySelector('.code-snippet');
        const fixCode = this.generateFixCode(reviewItem);

        if (codeSnippet) {
            // Toggle between original code and fixed code
            if (codeSnippet.dataset.showingFix === 'true') {
                // Reset to original
                codeSnippet.dataset.showingFix = 'false';
                codeSnippet.querySelector('pre').textContent = codeSnippet.dataset.originalCode;
                btn.textContent = 'Show Fix';
            } else {
                // Show fixed code
                if (!codeSnippet.dataset.originalCode) {
                    codeSnippet.dataset.originalCode = codeSnippet.querySelector('pre').textContent;
                }
                codeSnippet.dataset.showingFix = 'true';
                codeSnippet.querySelector('pre').textContent = fixCode;
                btn.textContent = 'Show Original';
            }
        } else {
            // Create a new code snippet with the fix
            const newSnippet = document.createElement('div');
            newSnippet.className = 'code-snippet';
            newSnippet.dataset.showingFix = 'true';
            newSnippet.innerHTML = `<pre>${fixCode}</pre>`;
            reviewItem.appendChild(newSnippet);
            btn.textContent = 'Show Original';
        }
    },

    // Generate fixed code for an issue
    generateFixCode(reviewItem) {
        if (!reviewItem) return '';

        // In a real application, this would come from the API
        // For demo purposes, we're using hard-coded examples

        const issueType = reviewItem.classList.contains('error') ? 'error' :
            reviewItem.classList.contains('warning') ? 'warning' :
                reviewItem.classList.contains('improvement') ? 'improvement' : 'security';

        const issueTitle = reviewItem.querySelector('strong')?.textContent || '';

        // Return fixed code based on issue type
        switch (issueType) {
            case 'error':
                return "// Use parameterized query to prevent SQL injection\nconst query = \"SELECT * FROM users WHERE username = ?\";\ndb.query(query, [username], (err, results) => { /* handle results */ });";
            case 'warning':
                return "// Fetch all user roles in a single query\nconst userIds = users.map(user => user.id);\nconst roles = await db.query(\"SELECT * FROM roles WHERE user_id IN (?)\", [userIds]);\n\n// Create a map for easy lookup\nconst userRolesMap = {};\nroles.forEach(role => {\n  if (!userRolesMap[role.user_id]) userRolesMap[role.user_id] = [];\n  userRolesMap[role.user_id].push(role);\n});";
            case 'improvement':
                return "// Extract validation to a reusable function\nfunction isValidEmail(email) {\n  return email && email.includes('@') && email.includes('.');\n}\n\n// Usage\nif (!isValidEmail(email)) {\n  return res.status(400).send('Invalid email');\n}";
            default:
                return "// Update package.json\n\"dependencies\": {\n  \"crypto-js\": \"^4.1.1\", // Updated from 3.1.9\n  // other dependencies\n}";
        }
    },

    // Ignore an issue
    ignoreIssue(event) {
        const btn = event.currentTarget;
        const reviewItem = btn.closest('.review-item');
        if (!reviewItem) return;

        // Add ignored class and fade out
        reviewItem.classList.add('text-muted');
        reviewItem.style.opacity = '0.5';

        // Update the button text
        btn.textContent = 'Ignored';
        btn.disabled = true;

        // In a real app, we would send this info to the backend
    }
};
