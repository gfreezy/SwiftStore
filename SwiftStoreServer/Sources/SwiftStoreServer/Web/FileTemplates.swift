import Foundation

/// HTML templates for the File Management UI
enum FileTemplates {
    /// File management page HTML
    static let filePage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SwiftStore Admin - Files</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                background-color: #f5f5f5;
                color: #333;
            }

            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 0px 24px;
                font-size: 20px;
                font-weight: 600;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                display: flex;
                align-items: center;
                gap: 24px;
                height: 56px;
            }

            .header-title {
                font-size: 20px;
                font-weight: 600;
            }

            .header-nav {
                display: flex;
                gap: 8px;
            }

            .header-nav a {
                color: rgba(255, 255, 255, 0.7);
                text-decoration: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-size: 14px;
                font-weight: 500;
                transition: all 0.2s;
            }

            .header-nav a:hover {
                background: rgba(255, 255, 255, 0.1);
                color: white;
            }

            .header-nav a.active {
                background: rgba(255, 255, 255, 0.2);
                color: white;
            }

            .container {
                max-width: 1400px;
                margin: 0 auto;
                padding: 20px;
            }

            .toolbar {
                background: white;
                border-radius: 8px;
                padding: 16px;
                margin-bottom: 16px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                display: flex;
                align-items: center;
                gap: 16px;
                flex-wrap: wrap;
            }

            .path-display {
                display: flex;
                align-items: center;
                gap: 8px;
                flex: 1;
                min-width: 200px;
            }

            .path-icon {
                font-size: 20px;
            }

            .breadcrumb {
                display: flex;
                align-items: center;
                gap: 4px;
                font-size: 14px;
                color: #555;
                overflow-x: auto;
                white-space: nowrap;
            }

            .breadcrumb a {
                color: #667eea;
                text-decoration: none;
                padding: 4px 8px;
                border-radius: 4px;
            }

            .breadcrumb a:hover {
                background: #f0f0f0;
            }

            .breadcrumb-sep {
                color: #ccc;
            }

            .breadcrumb-current {
                padding: 4px 8px;
                font-weight: 500;
            }

            .toolbar-actions {
                display: flex;
                gap: 8px;
            }

            .btn {
                padding: 10px 16px;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-weight: 500;
                font-size: 14px;
                transition: all 0.2s;
                display: flex;
                align-items: center;
                gap: 6px;
            }

            .btn-primary {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }

            .btn-primary:hover {
                transform: translateY(-1px);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
            }

            .btn-secondary {
                background: #f0f0f0;
                color: #333;
            }

            .btn-secondary:hover {
                background: #e0e0e0;
            }

            .file-table-container {
                background: white;
                border-radius: 8px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                overflow: hidden;
            }

            table {
                width: 100%;
                border-collapse: collapse;
            }

            th {
                background: #f8f9fa;
                padding: 12px 16px;
                text-align: left;
                font-weight: 600;
                color: #555;
                border-bottom: 2px solid #e0e0e0;
                position: sticky;
                top: 0;
            }

            th:first-child {
                width: 40px;
            }

            td {
                padding: 12px 16px;
                border-bottom: 1px solid #f0f0f0;
            }

            tr:hover {
                background-color: #f8f9fa;
            }

            tr.clickable {
                cursor: pointer;
            }

            tr.clickable:hover {
                background-color: #e8f0fe;
            }

            .file-icon {
                font-size: 20px;
            }

            .file-name {
                font-weight: 500;
            }

            .file-name a {
                color: #333;
                text-decoration: none;
            }

            .file-name a:hover {
                color: #667eea;
            }

            .file-size, .file-modified {
                color: #666;
                font-size: 13px;
            }

            .file-actions {
                text-align: right;
                white-space: nowrap;
            }

            .file-actions a {
                color: #667eea;
                text-decoration: none;
                padding: 4px 8px;
                border-radius: 4px;
                margin-left: 4px;
            }

            .file-actions a:hover {
                background: #e8f0fe;
            }

            .file-name a {
                color: #333;
                text-decoration: none;
            }

            .file-name a:hover {
                color: #667eea;
                text-decoration: underline;
            }

            .empty-state {
                text-align: center;
                padding: 60px 20px;
                color: #999;
            }

            .empty-state-icon {
                font-size: 48px;
                margin-bottom: 16px;
            }

            .loading {
                text-align: center;
                padding: 40px;
                color: #666;
            }

            .spinner {
                display: inline-block;
                width: 24px;
                height: 24px;
                border: 3px solid #f0f0f0;
                border-top-color: #667eea;
                border-radius: 50%;
                animation: spin 1s linear infinite;
            }

            @keyframes spin {
                to { transform: rotate(360deg); }
            }

            .error-message {
                background: #fee;
                color: #c00;
                padding: 12px 16px;
                border-radius: 6px;
                margin-bottom: 16px;
                border: 1px solid #fcc;
            }

            .success-message {
                background: #efe;
                color: #060;
                padding: 12px 16px;
                border-radius: 6px;
                margin-bottom: 16px;
                border: 1px solid #cfc;
            }

            /* Upload modal */
            .modal-overlay {
                display: none;
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                z-index: 1000;
                justify-content: center;
                align-items: center;
            }

            .modal-overlay.visible {
                display: flex;
            }

            .modal {
                background: white;
                border-radius: 8px;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
                width: 90%;
                max-width: 500px;
            }

            .modal-header {
                padding: 16px;
                border-bottom: 1px solid #e0e0e0;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }

            .modal-title {
                font-weight: 600;
                font-size: 16px;
            }

            .modal-close {
                background: none;
                border: none;
                font-size: 24px;
                cursor: pointer;
                color: #666;
                padding: 0 8px;
            }

            .modal-close:hover {
                color: #333;
            }

            .modal-body {
                padding: 20px;
            }

            .upload-zone {
                border: 2px dashed #ddd;
                border-radius: 8px;
                padding: 40px 20px;
                text-align: center;
                cursor: pointer;
                transition: all 0.2s;
            }

            .upload-zone:hover, .upload-zone.dragover {
                border-color: #667eea;
                background: #f8f9ff;
            }

            .upload-zone-icon {
                font-size: 48px;
                color: #ccc;
                margin-bottom: 16px;
            }

            .upload-zone-text {
                color: #666;
                margin-bottom: 8px;
            }

            .upload-zone-hint {
                color: #999;
                font-size: 13px;
            }

            .upload-progress {
                display: none;
                margin-top: 20px;
            }

            .upload-progress.visible {
                display: block;
            }

            .progress-bar {
                height: 8px;
                background: #f0f0f0;
                border-radius: 4px;
                overflow: hidden;
            }

            .progress-bar-fill {
                height: 100%;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                width: 0%;
                transition: width 0.3s;
            }

            .progress-text {
                margin-top: 8px;
                font-size: 13px;
                color: #666;
                text-align: center;
            }

            #fileInput {
                display: none;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <span class="header-title">SwiftStore Admin</span>
            <nav class="header-nav">
                <a href="/admin">Database</a>
                <a href="/files" class="active">Files</a>
            </nav>
        </div>

        <div class="container">
            <div id="messageContainer"></div>

            <div class="toolbar">
                <div class="path-display">
                    <span class="path-icon">📁</span>
                    <div class="breadcrumb" id="breadcrumb">
                        <a href="#" onclick="navigateTo('/')">Root</a>
                    </div>
                </div>
                <div class="toolbar-actions">
                    <button class="btn btn-primary" onclick="showUploadModal()" id="uploadBtn">
                        <span>⬆</span> Upload
                    </button>
                    <button class="btn btn-secondary" onclick="refresh()">
                        <span>🔄</span> Refresh
                    </button>
                </div>
            </div>

            <div class="file-table-container">
                <table>
                    <thead>
                        <tr>
                            <th>Type</th>
                            <th>Name</th>
                            <th>Size</th>
                            <th>Modified</th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody id="fileList">
                        <tr><td colspan="5" class="loading"><div class="spinner"></div></td></tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Upload Modal -->
        <div class="modal-overlay" id="uploadModal" onclick="closeModalOnOverlay(event)">
            <div class="modal">
                <div class="modal-header">
                    <span class="modal-title">Upload File</span>
                    <button class="modal-close" onclick="closeUploadModal()">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="upload-zone" id="uploadZone" onclick="document.getElementById('fileInput').click()">
                        <div class="upload-zone-icon">📤</div>
                        <div class="upload-zone-text">Click to select a file or drag and drop</div>
                        <div class="upload-zone-hint">Maximum file size: <span id="maxSizeDisplay">50MB</span></div>
                    </div>
                    <input type="file" id="fileInput" onchange="handleFileSelect(event)">
                    <div class="upload-progress" id="uploadProgress">
                        <div class="progress-bar">
                            <div class="progress-bar-fill" id="progressFill"></div>
                        </div>
                        <div class="progress-text" id="progressText">Uploading...</div>
                    </div>
                </div>
            </div>
        </div>

        <script>
            // State
            let currentPath = '/';
            let allowUpload = true;

            // Initialize
            document.addEventListener('DOMContentLoaded', function() {
                // Setup drag and drop
                const uploadZone = document.getElementById('uploadZone');
                uploadZone.addEventListener('dragover', function(e) {
                    e.preventDefault();
                    this.classList.add('dragover');
                });
                uploadZone.addEventListener('dragleave', function(e) {
                    this.classList.remove('dragover');
                });
                uploadZone.addEventListener('drop', function(e) {
                    e.preventDefault();
                    this.classList.remove('dragover');
                    if (e.dataTransfer.files.length > 0) {
                        uploadFile(e.dataTransfer.files[0]);
                    }
                });

                // Handle browser back/forward
                window.addEventListener('popstate', function(e) {
                    const path = e.state?.path || '/';
                    loadDirectory(path, false);
                });

                // Load initial directory from URL or default to root
                const urlParams = new URLSearchParams(window.location.search);
                const initialPath = urlParams.get('path') || '/';
                loadDirectory(initialPath, true);
            });

            // API calls
            async function loadDirectory(path, pushState = true) {
                currentPath = path;
                updateBreadcrumb(path);

                // Update browser history
                if (pushState) {
                    const url = path === '/' ? '/files' : '/files?path=' + encodeURIComponent(path);
                    history.pushState({ path: path }, '', url);
                }

                const fileList = document.getElementById('fileList');
                fileList.innerHTML = '<tr><td colspan="5" class="loading"><div class="spinner"></div></td></tr>';

                try {
                    const response = await fetch('/api/files/list?path=' + encodeURIComponent(path));
                    const data = await response.json();

                    if (!data.success) {
                        showError(data.error || 'Failed to load directory');
                        fileList.innerHTML = '<tr><td colspan="5" class="empty-state"><div class="empty-state-icon">❌</div><p>' + escapeHtml(data.error || 'Failed to load') + '</p></td></tr>';
                        return;
                    }

                    renderFileList(data.items || []);
                } catch (error) {
                    showError('Failed to load directory: ' + error.message);
                    fileList.innerHTML = '<tr><td colspan="5" class="empty-state"><div class="empty-state-icon">❌</div><p>Failed to load directory</p></td></tr>';
                }
            }

            function renderFileList(items) {
                const fileList = document.getElementById('fileList');

                if (items.length === 0 && currentPath === '/') {
                    fileList.innerHTML = '<tr><td colspan="5" class="empty-state"><div class="empty-state-icon">📁</div><p>This directory is empty</p></td></tr>';
                    return;
                }

                let html = '';

                // Add parent directory link if not at root
                if (currentPath !== '/') {
                    const parentPath = getParentPath(currentPath);
                    html += `
                        <tr class="clickable" onclick="navigateTo('${escapeHtml(parentPath)}')">
                            <td class="file-icon">📁</td>
                            <td class="file-name">..</td>
                            <td class="file-size">-</td>
                            <td class="file-modified">-</td>
                            <td class="file-actions"></td>
                        </tr>
                    `;
                }

                for (const item of items) {
                    const icon = item.isDirectory ? '📁' : getFileIcon(item.name);
                    const size = item.isDirectory ? '-' : formatSize(item.size);
                    const modified = item.modified ? formatDate(item.modified) : '-';
                    const itemPath = joinPath(currentPath, item.name);

                    if (item.isDirectory) {
                        html += `
                            <tr class="clickable" onclick="navigateTo('${escapeHtml(itemPath)}')">
                                <td class="file-icon">${icon}</td>
                                <td class="file-name">${escapeHtml(item.name)}</td>
                                <td class="file-size">${size}</td>
                                <td class="file-modified">${modified}</td>
                                <td class="file-actions"></td>
                            </tr>
                        `;
                    } else {
                        html += `
                            <tr>
                                <td class="file-icon">${icon}</td>
                                <td class="file-name"><a href="/api/files/download?path=${encodeURIComponent(itemPath)}" target="_blank">${escapeHtml(item.name)}</a></td>
                                <td class="file-size">${size}</td>
                                <td class="file-modified">${modified}</td>
                                <td class="file-actions">
                                    <a href="/api/files/download?path=${encodeURIComponent(itemPath)}&download=true">Download</a>
                                </td>
                            </tr>
                        `;
                    }
                }

                fileList.innerHTML = html;
            }

            function navigateTo(path) {
                loadDirectory(path, true);
            }

            function refresh() {
                loadDirectory(currentPath, false);
            }

            // Upload
            function showUploadModal() {
                document.getElementById('uploadModal').classList.add('visible');
                document.getElementById('uploadProgress').classList.remove('visible');
            }

            function closeUploadModal() {
                document.getElementById('uploadModal').classList.remove('visible');
            }

            function closeModalOnOverlay(event) {
                if (event.target.id === 'uploadModal') {
                    closeUploadModal();
                }
            }

            function handleFileSelect(event) {
                const file = event.target.files[0];
                if (file) {
                    uploadFile(file);
                }
            }

            async function uploadFile(file) {
                const progressContainer = document.getElementById('uploadProgress');
                const progressFill = document.getElementById('progressFill');
                const progressText = document.getElementById('progressText');

                progressContainer.classList.add('visible');
                progressFill.style.width = '0%';
                progressText.textContent = 'Uploading ' + file.name + '...';

                const formData = new FormData();
                formData.append('file', file);
                formData.append('path', currentPath);

                try {
                    const xhr = new XMLHttpRequest();

                    xhr.upload.addEventListener('progress', function(e) {
                        if (e.lengthComputable) {
                            const percent = (e.loaded / e.total) * 100;
                            progressFill.style.width = percent + '%';
                            progressText.textContent = 'Uploading ' + file.name + '... ' + Math.round(percent) + '%';
                        }
                    });

                    xhr.onload = function() {
                        try {
                            const response = JSON.parse(xhr.responseText);
                            if (response.success) {
                                showSuccess('File uploaded successfully: ' + response.filename);
                                closeUploadModal();
                                refresh();
                            } else {
                                showError(response.error || 'Upload failed');
                                progressText.textContent = 'Upload failed';
                            }
                        } catch (e) {
                            showError('Upload failed: Invalid response');
                            progressText.textContent = 'Upload failed';
                        }
                    };

                    xhr.onerror = function() {
                        showError('Upload failed: Network error');
                        progressText.textContent = 'Upload failed';
                    };

                    xhr.open('POST', '/api/files/upload');
                    xhr.send(formData);

                } catch (error) {
                    showError('Upload failed: ' + error.message);
                    progressText.textContent = 'Upload failed';
                }

                // Reset file input
                document.getElementById('fileInput').value = '';
            }

            // UI helpers
            function updateBreadcrumb(path) {
                const breadcrumb = document.getElementById('breadcrumb');
                const parts = path.split('/').filter(p => p);

                let html = '<a href="#" onclick="navigateTo(\\'/\\')">Root</a>';

                let currentBuiltPath = '';
                for (let i = 0; i < parts.length; i++) {
                    currentBuiltPath += '/' + parts[i];
                    html += '<span class="breadcrumb-sep">/</span>';

                    if (i === parts.length - 1) {
                        html += '<span class="breadcrumb-current">' + escapeHtml(parts[i]) + '</span>';
                    } else {
                        html += '<a href="#" onclick="navigateTo(\\'' + escapeHtml(currentBuiltPath) + '\\')">' + escapeHtml(parts[i]) + '</a>';
                    }
                }

                breadcrumb.innerHTML = html;
            }

            function showError(message) {
                const container = document.getElementById('messageContainer');
                container.innerHTML = '<div class="error-message">' + escapeHtml(message) + '</div>';
                setTimeout(() => { container.innerHTML = ''; }, 5000);
            }

            function showSuccess(message) {
                const container = document.getElementById('messageContainer');
                container.innerHTML = '<div class="success-message">' + escapeHtml(message) + '</div>';
                setTimeout(() => { container.innerHTML = ''; }, 5000);
            }

            // Utility functions
            function escapeHtml(text) {
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            }

            function getParentPath(path) {
                const parts = path.split('/').filter(p => p);
                parts.pop();
                return '/' + parts.join('/');
            }

            function joinPath(base, name) {
                if (base === '/') return '/' + name;
                return base + '/' + name;
            }

            function formatSize(bytes) {
                if (bytes === null || bytes === undefined) return '-';
                if (bytes < 1024) return bytes + ' B';
                if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
                if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
                return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
            }

            function formatDate(dateString) {
                const date = new Date(dateString);
                return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'});
            }

            function getFileIcon(filename) {
                const ext = filename.split('.').pop().toLowerCase();
                const icons = {
                    // Documents
                    'pdf': '📕',
                    'doc': '📘', 'docx': '📘',
                    'xls': '📗', 'xlsx': '📗',
                    'ppt': '📙', 'pptx': '📙',
                    'txt': '📄',
                    'md': '📝',

                    // Code
                    'swift': '🔶',
                    'js': '💛', 'ts': '💙',
                    'py': '🐍',
                    'html': '🌐', 'css': '🎨',
                    'json': '📋', 'xml': '📋',
                    'sql': '🗃️',

                    // Images
                    'jpg': '🖼️', 'jpeg': '🖼️', 'png': '🖼️', 'gif': '🖼️', 'svg': '🖼️', 'webp': '🖼️',

                    // Archives
                    'zip': '📦', 'tar': '📦', 'gz': '📦', 'rar': '📦', '7z': '📦',

                    // Media
                    'mp3': '🎵', 'wav': '🎵', 'flac': '🎵',
                    'mp4': '🎬', 'mov': '🎬', 'avi': '🎬', 'webm': '🎬',

                    // Database
                    'sqlite': '🗄️', 'db': '🗄️'
                };
                return icons[ext] || '📄';
            }

            // Keyboard shortcuts
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    closeUploadModal();
                }
            });
        </script>
    </body>
    </html>
    """
}
