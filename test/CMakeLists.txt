# Define the executable
add_executable(TestHarness test_harness.m)

# Link the executable against the MediaRemoteAdapter framework
target_link_libraries(TestHarness PRIVATE MediaRemoteAdapter)

# Set the runpath so the executable can find the framework at runtime
set_target_properties(TestHarness PROPERTIES
    INSTALL_RPATH "@executable_path/../"
) 