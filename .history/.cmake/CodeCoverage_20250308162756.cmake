# =============================================================================
# Code coverage support module
# =============================================================================

# Check prerequisites
find_program(GCOV_PATH gcov)
find_program(LCOV_PATH lcov)
find_program(GENHTML_PATH genhtml)

if(NOT GCOV_PATH)
    message(FATAL_ERROR "gcov not found! Aborting...")
endif()

# Target for code coverage
function(SETUP_TARGET_FOR_COVERAGE)
    set(options "")
    set(oneValueArgs TARGET_NAME OUTPUT_DIR)
    set(multiValueArgs EXCLUDE EXECUTABLE EXECUTABLE_ARGS DEPENDENCIES)
    cmake_parse_arguments(COVERAGE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Setup compiler options
    add_compile_options(--coverage -O0 -g)
    add_link_options(--coverage)
    
    # Create directory for coverage results
    file(MAKE_DIRECTORY ${COVERAGE_OUTPUT_DIR})
    
    # Create the coverage target
    add_custom_target(${COVERAGE_TARGET_NAME}
        # Clean previous coverage data
        COMMAND ${LCOV_PATH} --directory . --zerocounters
        
        # Run the tests
        COMMAND $<TARGET_FILE:${COVERAGE_EXECUTABLE}> ${COVERAGE_EXECUTABLE_ARGS}
        
        # Capture coverage data
        COMMAND ${LCOV_PATH} --directory . --capture --output-file ${COVERAGE_OUTPUT_DIR}/coverage.info
        
        # Filter out unwanted data
        COMMAND ${LCOV_PATH} --remove ${COVERAGE_OUTPUT_DIR}/coverage.info ${COVERAGE_EXCLUDE} --output-file ${COVERAGE_OUTPUT_DIR}/coverage.info.cleaned
        
        # Generate HTML report
        COMMAND ${GENHTML_PATH} -o ${COVERAGE_OUTPUT_DIR} ${COVERAGE_OUTPUT_DIR}/coverage.info.cleaned
        
        # Display results
        COMMAND ${CMAKE_COMMAND} -E echo "Coverage report generated at ${COVERAGE_OUTPUT_DIR}/index.html"
        
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        DEPENDS ${COVERAGE_DEPENDENCIES}
        COMMENT "Generating code coverage report..."
    )
endfunction()
