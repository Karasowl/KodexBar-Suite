"""Built-in local AI runtime adapters.

Only adapters shipped with KodexBar are executable Python.  Extra integration
descriptors are JSON data, validated by the main program, never imported from
the user's configuration directory.
"""

from .builtin import builtin_drivers

__all__ = ["builtin_drivers"]
