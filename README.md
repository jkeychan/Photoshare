# PhotoShare

Welcome to the Personal PhotoSharing Application. This repository provides a Flask-based application that allows users to effortlessly share their personal photos, making it a perfect solution for those who want control over their media without depending on third-party platforms.

## Features

- **User Authentication**: Secure your media with a simple password-based login system.
- **Media Display**: Neatly organized and paginated view of all your media directories and files.
- **Download Capability**: Let your visitors download media directly from the web interface.
- **Easily Extensible**: With Flask/Gunicorn at its core, extending the application with additional features or integrations is a breeze.
  
## Pre-requisites


## Deployment

This application is designed to run on any cloud or server environment. For optimal performance and security, it is advised to front the application with an Nginx reverse proxy.

### Why Nginx?

Nginx acts as a shield in front of your application, handling incoming traffic and routing it to your application. It helps by:

1. **Load Balancing**: If you decide to scale your application, Nginx can distribute the load.
2. **Security**: Add an additional layer of security, protecting your application from various attacks.
3. **Caching**: Improve application speed by caching static files.
4. **SSL Termination**: Handle SSL handshakes and let your application run without that overhead.

### Deployment with Docker Compose

The provided Docker Compose script automates the deployment process. It sets up the Flask application alongside the Nginx reverse proxy, ensuring they work seamlessly together.

The Docker Compose setup also allows you to mount your media directory from a local drive, ensuring that all your media remains under your control.

## Setup & Configuration

1. **Clone the Repository**:


Contribution
Feel free to fork the repository and make enhancements. Pull requests are more than welcome!

License
MIT License