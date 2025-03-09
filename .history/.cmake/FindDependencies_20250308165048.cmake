# =============================================================================
# Module for finding and configuring dependencies
# =============================================================================

include(FetchContent)

# Set default download progress
set(FETCHCONTENT_QUIET OFF)

# Function to download and configure a dependency
function(fetch_dependency NAME GIT_REPO GIT_TAG)
    string(TOLOWER ${NAME} NAME_LOWER)
    
    # Don't fetch if using system dependencies
    if(USE_SYSTEM_DEPS)
        find_package(${NAME} QUIET)
        if(${NAME}_FOUND OR ${NAME_LOWER}_FOUND)
            message(STATUS "Using system ${NAME}")
            return()
        else()
            message(STATUS "System ${NAME} not found, will download")
        endif()
    endif()
    
    # Check if already fetched
    if(${NAME}_POPULATED OR ${NAME_LOWER}_POPULATED)
        message(STATUS "${NAME} already fetched")
        return()
    endif()
    
    message(STATUS "Fetching ${NAME} from ${GIT_REPO}")
    
    FetchContent_Declare(
        ${NAME}
        GIT_REPOSITORY ${GIT_REPO}
        GIT_TAG ${GIT_TAG}
        GIT_SHALLOW TRUE
        GIT_PROGRESS TRUE
    )
    
    FetchContent_MakeAvailable(${NAME})
endfunction()

# Function to find Python packages and install if missing
function(ensure_python_package PACKAGE_NAME)
    execute_process(
        COMMAND ${Python3_EXECUTABLE} -c "import ${PACKAGE_NAME}"
        RESULT_VARIABLE EXIT_CODE
        OUTPUT_QUIET
        ERROR_QUIET
    )
    
    if(NOT ${EXIT_CODE} EQUAL 0)
        message(STATUS "Python package '${PACKAGE_NAME}' not found, installing...")
        execute_process(
            COMMAND ${Python3_EXECUTABLE} -m pip install ${PACKAGE_NAME}
            RESULT_VARIABLE PIP_RESULT
        )
        
        if(NOT ${PIP_RESULT} EQUAL 0)
            message(WARNING "Failed to install Python package '${PACKAGE_NAME}'")
        else()
            message(STATUS "Successfully installed '${PACKAGE_NAME}'")
        endif()
    else()
        message(STATUS "Python package '${PACKAGE_NAME}' is already installed")
    endif()
endfunction()

# Function to download and configure Node.js dependencies
function(ensure_npm_package PACKAGE_NAME VERSION)
    # Check if Node.js is available
    find_program(NODE_EXECUTABLE node)
    find_program(NPM_EXECUTABLE npm)
    
    if(NOT NODE_EXECUTABLE OR NOT NPM_EXECUTABLE)
        message(WARNING "Node.js or npm not found, skipping npm package installation")
        return()
    endif()
    
    # Check if the package is installed globally
    execute_process(
        COMMAND ${NPM_EXECUTABLE} list -g ${PACKAGE_NAME}
        RESULT_VARIABLE EXIT_CODE
        OUTPUT_QUIET
        ERROR_QUIET
    )
    
    # Install if not found or version doesn't match
    if(NOT ${EXIT_CODE} EQUAL 0)
        message(STATUS "Installing npm package '${PACKAGE_NAME}@${VERSION}'...")
        execute_process(
            COMMAND ${NPM_EXECUTABLE} install -g ${PACKAGE_NAME}@${VERSION}
            RESULT_VARIABLE NPM_RESULT
        )
        
        if(NOT ${NPM_RESULT} EQUAL 0)
            message(WARNING "Failed to install npm package '${PACKAGE_NAME}'")
        else()
            message(STATUS "Successfully installed '${PACKAGE_NAME}@${VERSION}'")
        endif()
    else()
        message(STATUS "Npm package '${PACKAGE_NAME}' is already installed")
    endif()
endfunction()

# Example dependencies (enable as needed)
# fetch_dependency(
#    GoogleTest 
#    https://github.com/google/googletest.git 
#    release-1.11.0
# )

# Common Python packages needed for development
ensure_python_package(pytest)
ensure_python_package(black)
ensure_python_package(flake8)
ensure_python_package(isort)
