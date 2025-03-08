#!/usr/bin/env python
"""
AI-powered code review script for pre-commit hook.

This script sends code changes to a local Watsonx Code Assistant API
for automated review before commit. It provides insights on:
- Code quality
- Potential bugs
- Security vulnerabilities
- Performance issues
- Best practices
"""

import argparse
import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import requests


class AICodeReviewer:
    """AI-powered code reviewer using Watsonx Code Assistant."""

    def __init__(self, api_url: str = "http://localhost:11434/api"):
        """Initialize the code reviewer.
        
        Args:
            api_url: URL of the Ollama API
        """
        self.api_url = api_url
        self.model = os.environ.get("WATSONX_MODEL", "granite-code:8b")
        self.max_tokens = int(os.environ.get("WATSONX_MAX_TOKENS", "2048"))
        self.temperature = float(os.environ.get("WATSONX_TEMPERATURE", "0.1"))
        self.exit_on_errors = os.environ.get("EXIT_ON_ERRORS", "false").lower() == "true"
        self.severity_threshold = os.environ.get("SEVERITY_THRESHOLD", "medium")
    
    def get_diff(self, file_path: str) -> str:
        """Get git diff for a file.
        
        Args:
            file_path: Path to the file
            
        Returns:
            String containing the git diff
        """
        try:
            # Get diff for staged changes
            result = subprocess.run(
                ["git", "diff", "--staged", file_path],
                capture_output=True,
                text=True,
                check=True
            )
            diff = result.stdout.strip()
            
            # If no staged changes, get diff for unstaged changes
            if not diff:
                result = subprocess.run(
                    ["git", "diff", file_path],
                    capture_output=True,
                    text=True,
                    check=True
                )
                diff = result.stdout.strip()
                
            return diff
        except subprocess.CalledProcessError as e:
            print(f"Error getting diff for {file_path}: {e}")
            return ""
    
    def get_file_context(self, file_path: str) -> str:
        """Get the full file content for context.
        
        Args:
            file_path: Path to the file
            
        Returns:
            String containing the file content
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
            return ""
    
    def generate_review_prompt(self, file_path: str, diff: str, context: str) -> str:
        """Generate a prompt for the AI to review code changes.
        
        Args:
            file_path: Path to the file
            diff: Git diff for the file
            context: Full file content
            
        Returns:
            Prompt string for the AI
        """
        file_extension = Path(file_path).suffix
        
        return textwrap.dedent(f"""
        You are an expert code reviewer. Review the following code changes and provide feedback.
        Focus on:
        1. Bugs or logical errors
        2. Security vulnerabilities
        3. Performance issues
        4. Code style and best practices
        5. Potential edge cases

        For each issue found:
        - Indicate severity (HIGH/MEDIUM/LOW)
        - Explain the issue clearly
        - Provide a recommended fix

        File: {file_path}
        Language: {file_extension}

        === CODE DIFF ===
        {diff if diff else "No diff available"}

        === FILE CONTEXT ===
        {context[:10000] if context else "No context available"}

        Provide your review in this format:
        ISSUE 1:
        - Severity: [HIGH|MEDIUM|LOW]
        - Line number: [line number]
        - Issue: [description]
        - Recommendation: [fix]

        ISSUE 2:
        ...

        SUMMARY:
        [overall assessment of the changes]
        """).strip()
    
    def review_code(self, file_path: str) -> Tuple[bool, str]:
        """Review code changes using AI.
        
        Args:
            file_path: Path to the file
            
        Returns:
            Tuple (success, review_text)
        """
        diff = self.get_diff(file_path)
        context = self.get_file_context(file_path)
        
        if not diff:
            print(f"No changes detected for {file_path}")
            return True, ""
            
        prompt = self.generate_review_prompt(file_path, diff, context)
        
        try:
            response = requests.post(
                f"{self.api_url}/generate",
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "max_tokens": self.max_tokens,
                    "temperature": self.temperature,
                    "system": "You are an expert code reviewer who helps find and fix issues in code."
                },
                timeout=30
            )
            
            response.raise_for_status()
            result = response.json()
            review = result.get("response", "No review generated")
            
            # Check if there are any high severity issues
            success = "Severity: HIGH" not in review
            if self.severity_threshold == "low":
                success = "Severity: " not in review
            elif self.severity_threshold == "medium":
                success = "Severity: HIGH" not in review
            
            return success, review
            
        except Exception as e:
            print(f"Error contacting AI service: {e}")
            return not self.exit_on_errors, f"Error generating review: {e}"
    
    def print_review(self, file_path: str, review: str) -> None:
        """Print the review in a formatted way.
        
        Args:
            file_path: Path to the file
            review: Review text
        """
        print("\n" + "=" * 80)
        print(f"AI CODE REVIEW FOR: {file_path}")
        print("=" * 80)
        print(review)
        print("-" * 80)


def main():
    parser = argparse.ArgumentParser(description="AI Code Review pre-commit hook")
    parser.add_argument("files", nargs="*", help="Files to review")
    args = parser.parse_args()
    
    reviewer = AICodeReviewer()
    all_success = True
    
    for file_path in args.files:
        if not os.path.isfile(file_path):
            continue
            
        # Skip files that are likely to be binary
        if Path(file_path).suffix.lower() in ['.png', '.jpg', '.jpeg', '.gif', '.ico', '.woff', '.ttf', '.eot']:
            continue
            
        success, review = reviewer.review_code(file_path)
        if review:
            reviewer.print_review(file_path, review)
            
        if not success:
            all_success = False
            print(f"⚠️  Issues found in {file_path}")
    
    if not all_success and reviewer.exit_on_errors:
        print("\n❌ AI code review found issues. Please fix them before committing.")
        sys.exit(1)
    else:
        print("\n✅ AI code review completed.")


if __name__ == "__main__":
    main()
