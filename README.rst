∇·∇
---
In math, the Laplacian operator is the divergence of the gradiant. Its use
appears in various applications of math and science. On very non scientific use
is in image precessing where the Laplacian pulls out areas of sharp contrast.
In other words, this operator returns the edges of an image. The
`Laplacian <https://en.wikipedia.org/wiki/Laplace_operator>`__ wikipedia page
provides more info.

The typical Laplacian in image processing is a kernel of the form
.. code::

    |  0  1  0  |
    |  1 -4  1  |
    |  0  1  0  |

.. .. math::

..     \begin{bmatrix}
..     0 & 1 & 0 \\
..     1 & -4 & 1\\
..     0 & 1 & 0
..     \end{bmatrix}

.. .. image:: foo.jpg
..    :target: https://latex.codecogs.com/gif.latex?\begin{bmatrix}&space;0&space;&&space;1&space;&&space;0&space;\\&space;1&space;&&space;-4&space;&&space;1\\&space;0&space;&&space;1&space;&&space;0&space;\end{bmatrix}

This project implements a modification to the typical kernel Laplacian which
pulls out more edges.
.. code::

    |  1   2  1  |
    |  2 -12  2  |
    |  1   2  1  |
