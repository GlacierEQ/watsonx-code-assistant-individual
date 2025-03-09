"""
Test suite for the Watsonx Code Assistant API endpoints.

These tests verify the functionality and reliability of the API endpoints
that power the Watsonx Code Assistant UI.
"""

import json
import os
import unittest
from unittest.mock import MagicMock, patch

import pytest
import requests

# Path to the API server module (adjust as needed)
from start_ui_server import app


class TestAPIEndpoints(unittest.TestCase):
    """Test class for API endpoints."""
    
    def setUp(self):
        """Set up test environment before each test."""
        self.app = app.test_client()
        self.app.testing = True
    
    def test_health_endpoint(self):
        """Test the API health endpoint returns correct status."""
        response = self.app.get('/api/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'operational')
    
    @patch('start_ui_server.check_ollama_status')
    def test_system_status_endpoint(self, mock_check_ollama):
        """Test the system status endpoint."""
        # Mock the Ollama check to return a running status
        mock_check_ollama.return_value = {'status': 'running', 'port': 11434}
        
        response = self.app.get('/api/system/status')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        
        # Verify expected fields are present
        self.assertIn('ollama', data)
        self.assertIn('status', data['ollama'])
        self.assertEqual(data['ollama']['status'], 'running')
        
        # Check system resource fields
        self.assertIn('resources', data)
        self.assertIn('gpu', data['resources'])
        self.assertIn('memory', data['resources'])
    
    @patch('requests.post')
    def test_code_review_endpoint(self, mock_post):
        """Test the code review API endpoint."""
        # Mock the response from Ollama
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'response': 'No issues found. The code looks good.'
        }
        mock_post.return_value = mock_response
        
        # Test payload
        test_data = {
            'code': 'def example():\n    return "Hello World"',
            'language': 'python'
        }
        
        response = self.app.post(
            '/api/code/review',
            data=json.dumps(test_data),
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('review', data)
    
    def test_invalid_payload(self):
        """Test error handling for invalid request payload."""
        # Test with missing required fields
        invalid_data = {'language': 'python'}  # Missing code field
        
        response = self.app.post(
            '/api/code/review',
            data=json.dumps(invalid_data),
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.data)
        self.assertIn('error', data)
    
    @patch('start_ui_server.list_available_models')
    def test_models_available_endpoint(self, mock_list_models):
        """Test the available models endpoint."""
        # Mock available models
        mock_list_models.return_value = [
            {'name': 'granite-code:8b', 'size': '4.6 GB'},
            {'name': 'granite-code:3b', 'size': '2.4 GB'}
        ]
        
        response = self.app.get('/api/models/available')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('models', data)
        self.assertEqual(len(data['models']), 2)
        self.assertEqual(data['models'][0]['name'], 'granite-code:8b')


@pytest.mark.integration
class TestAPIEndpointsIntegration:
    """Integration tests for API endpoints against actual Ollama server."""
    
    @pytest.fixture
    def test_client(self):
        """Create a test client for the Flask app."""
        app.config['TESTING'] = True
        with app.test_client() as client:
            yield client
    
    @pytest.mark.skipif(not os.environ.get('RUN_INTEGRATION_TESTS'), 
                        reason="Integration tests not enabled")
    def test_ollama_connection(self, test_client):
        """Test actual connection to Ollama server."""
        response = test_client.get('/api/system/status')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'ollama' in data
    
    @pytest.mark.skipif(not os.environ.get('RUN_INTEGRATION_TESTS'), 
                        reason="Integration tests not enabled")
    def test_real_model_inference(self, test_client):
        """Test actual model inference via API."""
        test_data = {
            'prompt': 'Write a Python function to calculate factorial',
            'model': 'granite-code:8b',
            'temperature': 0.1,
            'max_tokens': 300
        }
        
        response = test_client.post(
            '/api/assistant/generate',
            data=json.dumps(test_data),
            content_type='application/json'
        )
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'response' in data
        assert len(data['response']) > 0


if __name__ == '__main__':
    unittest.main()
